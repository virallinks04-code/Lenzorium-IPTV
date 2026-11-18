import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import 'player_screen.dart';

/// EPG grid: channels down the side, time across. ◀ ▶ at the edge move
/// the window by 30 minutes; "Jump to now" returns to the current time.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const _windowMins = 150;
  late DateTime _start = _floorHalfHour(DateTime.now());
  String _cat = Category.allId;
  final _nowFocus = FocusNode();

  static DateTime _floorHalfHour(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);

  @override
  void dispose() {
    _nowFocus.dispose();
    super.dispose();
  }

  void _shift(int mins) => setState(() => _start = _start.add(Duration(minutes: mins)));

  Future<void> _pickCategory() async {
    final app = context.read<AppState>();
    final cats = [
      Category(id: Category.allId, name: 'All channels', kind: ContentKind.live),
      Category(id: Category.favId, name: 'Favourites', kind: ContentKind.live),
      ...app.db.categories(app.pid, ContentKind.live).where((c) => !app.settings.isLocked(app.pid, 'live', c.id)),
    ];
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Show channels'),
        children: [
          SizedBox(
            width: 420,
            height: 480,
            child: ListView(children: [
              for (final c in cats)
                MenuRow(label: c.name, selected: c.id == _cat, autofocus: c.id == _cat, onSelect: () => Navigator.of(ctx).pop(c.id)),
            ]),
          ),
        ],
      ),
    );
    if (id != null) setState(() => _cat = id);
  }

  Future<void> _open(Channel c, Programme? p, List<Channel> all) async {
    final now = DateTime.now();
    if (p == null || p.isOnAt(now)) {
      final pb = context.read<PlaybackController>();
      await pb.start(all.map(PlayItem.live).toList(), all.indexOf(c));
      if (mounted) push(context, const PlayerScreen());
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.name} · ${dayLong(p.start)} · ${hm(p.start)} – ${hm(p.stop)}', style: const TextStyle(color: LzColors.muted)),
            if (p.description.isNotEmpty) ...[const SizedBox(height: 12), Text(p.description, style: const TextStyle(height: 1.5))],
          ]),
        ),
        actions: [LzButton(label: 'Close', autofocus: true, onPressed: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final channels = app.db.channels(app.pid, _cat, hiddenCats: app.lockedCats(ContentKind.live));
    final compact = isCompact(context);
    final chanW = compact ? 120.0 : 220.0;
    final end = _start.add(const Duration(minutes: _windowMins));
    final now = DateTime.now();

    return ScreenFrame(
      title: 'TV guide',
      subtitle: dayLong(_start),
      actions: [
        if (app.epgSyncing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        LzButton(label: _cat == Category.allId ? 'All channels' : (_cat == Category.favId ? 'Favourites' : 'Category'), icon: Icons.filter_list, height: 44, onPressed: _pickCategory),
        LzButton(
          label: 'Jump to now',
          kind: LzButtonKind.primary,
          height: 44,
          onPressed: () => setState(() => _start = _floorHalfHour(DateTime.now())),
        ),
      ],
      child: LayoutBuilder(builder: (context, box) {
        final gridW = box.maxWidth - chanW;
        final pxPerMin = gridW / _windowMins;
        double x(DateTime t) => (t.difference(_start).inSeconds / 60.0 * pxPerMin).clamp(0.0, gridW);
        final nowX = now.isAfter(_start) && now.isBefore(end) ? chanW + x(now) : null;

        return Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 32,
              child: Row(children: [
                SizedBox(width: chanW, child: const Text('Channel', style: TextStyle(color: LzColors.muted, fontSize: 14))),
                for (var m = 0; m < _windowMins; m += 30)
                  Container(
                    width: 30 * pxPerMin,
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(border: Border(left: BorderSide(color: LzColors.line))),
                    child: Text(hm(_start.add(Duration(minutes: m))), style: const TextStyle(fontSize: 15, color: LzColors.textSoft)),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: channels.isEmpty
                  ? const EmptyState('No channels in this list.')
                  : ListView.builder(
                      itemCount: channels.length,
                      itemExtent: 70,
                      itemBuilder: (_, r) {
                        final c = channels[r];
                        final progs = app.db.programmes(app.pid, c.epgId, _start, end);
                        final cells = <Widget>[];
                        if (progs.isEmpty) {
                          cells.add(_cell(c, null, 0, 1, gridW - 4, 'No guide information', '', false, r == 0, channels));
                        } else {
                          var cursor = 0.0;
                          for (var i = 0; i < progs.length; i++) {
                            final p = progs[i];
                            final x0 = x(p.start.isBefore(_start) ? _start : p.start);
                            final x1 = x(p.stop.isAfter(end) ? end : p.stop);
                            if (x0 > cursor + 1) cells.add(SizedBox(width: x0 - cursor));
                            if (x1 - x0 < 20) continue; // too short to show
                            final w = (x1 - x0 - 4).clamp(24.0, gridW);
                            final live = p.isOnAt(now);
                            cells.add(_cell(c, p, i, progs.length, w, p.title, '${hm(p.start)} – ${hm(p.stop)}', live,
                                r == 0 && (live || (i == 0 && !progs.any((q) => q.isOnAt(now)))), channels));
                            cursor = x0 + w + 4;
                          }
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            SizedBox(
                              width: chanW,
                              child: Row(children: [
                                if (!compact) SizedBox(width: 40, child: Text('${c.number}', style: const TextStyle(fontSize: 14, color: LzColors.muted))),
                                SizedBox(width: 44, height: 30, child: LzImage(url: c.logo, label: c.name, radius: 6, fit: BoxFit.contain, monogramSize: 11)),
                                const SizedBox(width: 10),
                                if (!compact)
                                  Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                              ]),
                            ),
                            Expanded(
                              child: ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.centerLeft,
                                  maxWidth: double.infinity,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: cells.map((w) => Padding(padding: const EdgeInsets.only(right: 4), child: w)).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
          if (nowX != null)
            Positioned(top: 30, bottom: 0, left: nowX, child: IgnorePointer(child: Container(width: 2, color: LzColors.amber))),
        ]);
      }),
    );
  }

  Widget _cell(Channel c, Programme? p, int index, int count, double width, String title, String time, bool live, bool autofocus,
      List<Channel> all) {
    return SizedBox(
      width: width,
      height: 64,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft && index == 0) {
            _shift(-30);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowRight && index == count - 1) {
            _shift(30);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Focusable(
          autofocus: autofocus,
          radius: 10,
          ring: true,
          onSelect: () => _open(c, p, all),
          semanticLabel: '${c.name}: $title $time',
          builder: (_, f) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: f ? LzColors.surface3 : (live ? LzColors.surface2 : const Color(0xFF11151C)),
              border: Border.all(color: LzColors.surface2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (time.isNotEmpty && width > 90)
                Text(time, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 13, color: LzColors.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
