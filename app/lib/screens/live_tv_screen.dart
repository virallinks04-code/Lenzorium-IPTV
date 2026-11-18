import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
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

/// Categories on the left, channels in the middle, preview and now/next on
/// the right. OK once previews a channel; OK again opens it full screen.
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key, this.initialCategory = Category.allId});
  final String initialCategory;
  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  late String _cat = widget.initialCategory;
  List<Channel> _channels = [];
  Channel? _focused;
  int? _previewId;
  final Set<String> _unlocked = {};
  int _rev = -1;
  late final PlaybackController _pb = context.read<PlaybackController>();

  @override
  void initState() {
    super.initState();
    _pb; // capture before dispose
  }

  void _load() {
    final app = context.read<AppState>();
    final locked = app.lockedCats(ContentKind.live).difference(_unlocked);
    _channels = app.db.channels(app.pid, _cat, hiddenCats: locked);
    _focused ??= _channels.firstOrNull;
  }

  Future<void> _pickCategory(Category c) async {
    final app = context.read<AppState>();
    if (app.settings.isLocked(app.pid, 'live', c.id) && !_unlocked.contains(c.id)) {
      if (!await askPin(context)) return;
      _unlocked.add(c.id);
    }
    setState(() {
      _cat = c.id;
      _focused = null;
      _load();
    });
  }

  Future<void> _select(int index) async {
    final playback = context.read<PlaybackController>();
    final ch = _channels[index];
    final items = _channels.map(PlayItem.live).toList();
    if (isCompact(context) || _previewId == ch.id) {
      if (_previewId != ch.id) await playback.start(items, index);
      if (!mounted) return;
      await push(context, PlayerScreen(keepPlayingOnExit: !isCompact(context)));
      if (mounted) setState(() => _previewId = playback.isActive ? playback.current?.channel?.id : null);
    } else {
      await playback.start(items, index);
      setState(() => _previewId = ch.id);
    }
  }

  @override
  void dispose() {
    // Leaving Live TV stops the preview unless the mini-player took over.
    if (!_pb.mini) unawaited(_pb.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_rev != app.revision) {
      _rev = app.revision;
      _load();
    }
    final compact = isCompact(context);
    final cats = [
      Category(id: Category.allId, name: 'All channels', kind: ContentKind.live, count: app.db.count(app.pid, ContentKind.live)),
      Category(id: Category.favId, name: 'Favourites', kind: ContentKind.live),
      Category(id: Category.recentId, name: 'Recently watched', kind: ContentKind.live),
      ...app.db.categories(app.pid, ContentKind.live),
    ];
    final current = cats.where((c) => c.id == _cat).firstOrNull;
    final favs = app.db.favouriteKeys(app.pid, ContentKind.live);

    final catList = ListView.builder(
      itemCount: cats.length,
      itemBuilder: (_, i) {
        final c = cats[i];
        final locked = app.settings.isLocked(app.pid, 'live', c.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: MenuRow(
            label: c.name,
            icon: locked ? Icons.lock_outline : null,
            trailing: c.count > 0 ? '${c.count}' : null,
            selected: c.id == _cat,
            onSelect: () => _pickCategory(c),
          ),
        );
      },
    );

    final chanList = _channels.isEmpty
        ? EmptyState(_cat == Category.favId ? 'No favourite channels yet.\nPress the menu key (or F) on a channel to add it.' : 'No channels here.')
        : ListView.builder(
            itemCount: _channels.length,
            itemExtent: 76,
            itemBuilder: (_, i) {
              final c = _channels[i];
              return _ChannelRow(
                channel: c,
                autofocus: i == 0,
                favourite: favs.contains(c.streamId),
                playing: _previewId == c.id,
                onFocus: () => setState(() => _focused = c),
                onSelect: () => _select(i),
                onMenu: () {
                  final added = app.toggleFavourite(ContentKind.live, c.streamId);
                  toast(context, added ? 'Added ${c.name} to favourites' : 'Removed from favourites');
                },
              );
            },
          );

    return ScreenFrame(
      title: 'Live TV',
      subtitle: current == null ? null : '${current.name} · ${_channels.length} channels',
      hint: 'OK watch · Menu/F favourite',
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _Chip(label: cats[i].name, selected: cats[i].id == _cat, onTap: () => _pickCategory(cats[i])),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: chanList),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 240, child: FocusTraversalGroup(child: catList)),
              const SizedBox(width: 20),
              Expanded(child: FocusTraversalGroup(child: chanList)),
              const SizedBox(width: 20),
              SizedBox(width: 420, child: _PreviewPanel(channel: _focused, previewing: _previewId != null && _previewId == _focused?.id)),
            ]),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.favourite,
    required this.playing,
    required this.onFocus,
    required this.onSelect,
    required this.onMenu,
    this.autofocus = false,
  });

  final Channel channel;
  final bool favourite;
  final bool playing;
  final VoidCallback onFocus;
  final VoidCallback onSelect;
  final VoidCallback onMenu;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Focusable(
          autofocus: autofocus,
          radius: 12,
          onSelect: onSelect,
          onMenu: onMenu,
          onFocusChange: (f) {
            if (f) onFocus();
          },
          semanticLabel: '${channel.number} ${channel.name}',
          builder: (_, focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: focused ? LzColors.surface2 : const Color(0xFF11151C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              SizedBox(width: 44, child: Text('${channel.number}', style: const TextStyle(fontSize: 15, color: LzColors.muted))),
              SizedBox(width: 54, height: 36, child: LzImage(url: channel.logo, label: channel.name, fit: BoxFit.contain)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              if (playing) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.graphic_eq, color: LzColors.accentText, size: 20)),
              if (favourite) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.star_rounded, color: LzColors.amber, size: 20)),
            ]),
          ),
        ),
      );
}

class _PreviewPanel extends StatefulWidget {
  const _PreviewPanel({required this.channel, required this.previewing});
  final Channel? channel;
  final bool previewing;
  @override
  State<_PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<_PreviewPanel> {
  Future<List<Programme>>? _epg;
  Timer? _debounce;
  int? _forId;

  @override
  void didUpdateWidget(covariant _PreviewPanel old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final c = widget.channel;
    if (c == null || c.id == _forId) return;
    _forId = c.id;
    _debounce?.cancel();
    // Wait for the D-pad to settle before asking the provider.
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _epg = context.read<AppState>().upcoming(c, count: 3));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    if (c == null) return const SizedBox.shrink();
    final pb = context.watch<PlaybackController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: const Color(0xFF1A2233),
            child: widget.previewing && pb.isActive && !pb.mini
                ? Stack(fit: StackFit.expand, children: [
                    Video(controller: pb.video, controls: NoVideoControls),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: LzColors.live, borderRadius: BorderRadius.circular(6)),
                        child: const Text('LIVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                      ),
                    ),
                  ])
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 120, height: 72, child: LzImage(url: c.logo, label: c.name, fit: BoxFit.contain, monogramSize: 22)),
                      const SizedBox(height: 10),
                      const Text('Press OK to preview', style: TextStyle(color: LzColors.faint, fontSize: 14)),
                    ]),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('${c.number} · ${c.name}', style: const TextStyle(fontSize: 14, color: LzColors.muted)),
      const SizedBox(height: 6),
      Expanded(
        child: FutureBuilder<List<Programme>>(
          future: _epg,
          builder: (_, snap) {
            final list = snap.data ?? const <Programme>[];
            if (snap.connectionState == ConnectionState.waiting) {
              return const Align(alignment: Alignment.topLeft, child: Text('Loading guide…', style: TextStyle(color: LzColors.muted)));
            }
            if (list.isEmpty) {
              return const Align(alignment: Alignment.topLeft, child: Text('No guide information for this channel.', style: TextStyle(color: LzColors.muted)));
            }
            final now = DateTime.now();
            final cur = list.first;
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cur.title, style: headline(24)),
                const SizedBox(height: 4),
                Text('${hm(cur.start)} – ${hm(cur.stop)}', style: const TextStyle(fontSize: 15, color: LzColors.muted)),
                const SizedBox(height: 12),
                if (cur.isOnAt(now)) ProgressBar(cur.progressAt(now), height: 6, color: LzColors.accent),
                if (cur.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(cur.description, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.5, color: LzColors.textSoft)),
                ],
                const SizedBox(height: 14),
                const Divider(color: LzColors.line),
                for (final (i, p) in list.skip(1).indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      SizedBox(width: 54, child: Text(i == 0 ? 'Next' : '', style: const TextStyle(color: LzColors.muted, fontSize: 15))),
                      SizedBox(width: 56, child: Text(hm(p.start), style: const TextStyle(color: LzColors.muted, fontSize: 15))),
                      Expanded(child: Text(p.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
        onSelect: onTap,
        radius: 999,
        ring: false,
        builder: (_, f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? LzColors.text : Colors.transparent,
            border: Border.all(color: selected ? LzColors.text : LzColors.lineStrong),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? LzColors.bg : LzColors.textSoft)),
        ),
      );
}
