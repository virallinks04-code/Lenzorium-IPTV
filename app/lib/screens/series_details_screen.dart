import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/focusable.dart';
import 'movie_details_screen.dart';
import 'player_screen.dart';

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({super.key, required this.series});
  final Series series;
  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  List<Episode> _eps = [];
  MediaDetails? _info;
  bool _loading = true;
  String? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final s = widget.series;
    _eps = app.db.episodes(app.pid, s.seriesId);
    final x = app.xtream;
    if (x != null) {
      try {
        final (info, eps) = await x.seriesInfo(s.seriesId);
        app.db.replaceEpisodes(app.pid, s.seriesId, eps);
        _info = info;
        _eps = eps;
      } catch (e) {
        if (_eps.isEmpty) _error = 'Could not load episodes. ${e.toString()}';
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      final next = _nextUp(app);
      _season = next?.$1.season ?? (_eps.isEmpty ? null : _eps.first.season);
    });
  }

  /// The episode to resume, or the one after the last finished episode.
  (Episode, Duration)? _nextUp(AppState app) {
    if (_eps.isEmpty) return null;
    HistoryItem? latest;
    for (final e in _eps) {
      final h = app.db.history(app.pid, 'episode', e.id);
      if (h != null && (latest == null || h.updated.isAfter(latest.updated))) latest = h;
    }
    if (latest == null) return (_eps.first, Duration.zero);
    final i = _eps.indexWhere((e) => e.id == latest!.key);
    if (i < 0) return (_eps.first, Duration.zero);
    if (latest.progress < 0.95) return (_eps[i], Duration(milliseconds: latest.positionMs));
    return i + 1 < _eps.length ? (_eps[i + 1], Duration.zero) : (_eps[i], Duration.zero);
  }

  Future<void> _play(Episode e, Duration at) async {
    final pb = context.read<PlaybackController>();
    final s = widget.series;
    final items = _eps.map((x) => PlayItem.ep(s, x, startAt: x.id == e.id ? at : Duration.zero)).toList();
    await pb.start(items, _eps.indexOf(e));
    if (mounted) await push(context, const PlayerScreen());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = widget.series;
    final fav = app.isFavourite(ContentKind.series, s.seriesId);
    final seasons = _eps.map((e) => e.season).toSet().toList()..sort();
    final next = _nextUp(app);
    final shown = _eps.where((e) => e.season == _season).toList();
    final info = _info;
    final meta = [
      if ((info?.year ?? s.year).isNotEmpty) info?.year ?? s.year,
      if (seasons.isNotEmpty) '${seasons.length} ${seasons.length == 1 ? 'season' : 'seasons'}',
      if (info != null && info.genre.isNotEmpty) info.genre,
      if ((info?.rating ?? s.rating).isNotEmpty && (info?.rating ?? s.rating) != '0') '★ ${info?.rating ?? s.rating}',
    ].join('  ·  ');

    return DetailsFrame(
      backdrop: info?.backdrop ?? s.poster,
      poster: s.poster,
      title: s.name,
      kicker: 'Series',
      meta: meta,
      plot: (info?.plot.isNotEmpty ?? false) ? info!.plot : s.plot,
      cast: info?.cast ?? '',
      buttons: [
        if (next != null)
          LzButton(
            label: next.$2 > Duration.zero ? 'Resume ${next.$1.code}' : 'Play ${next.$1.code}',
            icon: Icons.play_arrow,
            kind: LzButtonKind.primary,
            autofocus: true,
            onPressed: () => _play(next.$1, next.$2),
          ),
        if (_eps.isNotEmpty) LzButton(label: 'Play from start', icon: Icons.replay, onPressed: () => _play(_eps.first, Duration.zero)),
        LzButton(
          label: fav ? 'In favourites' : 'Add to favourites',
          icon: fav ? Icons.favorite : Icons.favorite_border,
          onPressed: () => app.toggleFavourite(ContentKind.series, s.seriesId),
        ),
      ],
      bottom: _loading
          ? const Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Loading episodes…')])
          : _error != null
              ? Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A)))
              : FocusTraversalGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final n in seasons)
                            Focusable(
                              radius: 999,
                              onSelect: () => setState(() => _season = n),
                              builder: (_, f) => Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: n == _season ? LzColors.text : (f ? LzColors.surface2 : Colors.transparent),
                                  border: Border.all(color: n == _season ? LzColors.text : LzColors.lineStrong),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('Season $n',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: n == _season ? LzColors.bg : LzColors.textSoft)),
                              ),
                            ),
                        ]),
                      ),
                      Text('Auto-play next episode: ${app.settings.autoPlayNext ? 'On' : 'Off'}', style: const TextStyle(fontSize: 14, color: LzColors.muted)),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (_, i) {
                          final e = shown[i];
                          final h = app.db.history(app.pid, 'episode', e.id);
                          return Focusable(
                            radius: 12,
                            onSelect: () => _play(e, h != null && h.progress < 0.95 ? Duration(milliseconds: h.positionMs) : Duration.zero),
                            semanticLabel: '${e.code} ${e.title}',
                            builder: (_, __) => SizedBox(
                              width: 240,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                SizedBox(
                                  height: 135,
                                  child: Stack(fit: StackFit.expand, children: [
                                    LzImage(url: e.image ?? s.poster, label: e.title, radius: 12),
                                    if (e.durationSecs > 0)
                                      Positioned(
                                        left: 10,
                                        bottom: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                          child: Text('${(e.durationSecs / 60).round()}m', style: const TextStyle(fontSize: 13)),
                                        ),
                                      ),
                                    if (h != null)
                                      Positioned(left: 0, right: 0, bottom: 0, child: ProgressBar(h.progress, color: Colors.white, track: Colors.black45)),
                                  ]),
                                ),
                                const SizedBox(height: 8),
                                Text('${e.episode} · ${e.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
    );
  }
}
