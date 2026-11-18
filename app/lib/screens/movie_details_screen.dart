import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/focusable.dart';
import 'player_screen.dart';

class MovieDetailsScreen extends StatefulWidget {
  const MovieDetailsScreen({super.key, required this.movie});
  final Movie movie;
  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  MediaDetails? _info;

  @override
  void initState() {
    super.initState();
    final x = context.read<AppState>().xtream;
    if (x != null) {
      x.vodInfo(widget.movie.streamId).then((i) {
        if (mounted) setState(() => _info = i);
      }).catchError((_) {});
    }
  }

  Future<void> _play(Duration at) async {
    final pb = context.read<PlaybackController>();
    await pb.start([PlayItem.movie(widget.movie, startAt: at)], 0);
    if (mounted) await push(context, const PlayerScreen());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final m = widget.movie;
    final h = app.db.history(app.pid, 'movie', m.streamId);
    final canResume = h != null && h.progress > 0.02 && h.progress < 0.95;
    final fav = app.isFavourite(ContentKind.movie, m.streamId);
    final info = _info;
    final meta = [
      if ((info?.year ?? m.year).isNotEmpty) info?.year ?? m.year,
      if (info != null && info.duration.isNotEmpty) info.duration,
      if (info != null && info.genre.isNotEmpty) info.genre,
      if ((info?.rating ?? m.rating).isNotEmpty && (info?.rating ?? m.rating) != '0') '★ ${info?.rating ?? m.rating}',
    ].join('  ·  ');

    return DetailsFrame(
      backdrop: info?.backdrop ?? m.poster,
      poster: m.poster,
      title: m.name,
      kicker: 'Movie',
      meta: meta,
      plot: info?.plot ?? '',
      cast: info?.cast ?? '',
      buttons: [
        if (canResume)
          LzButton(
            label: 'Resume · ${minutesLeft(h!.positionMs, h.durationMs)}',
            icon: Icons.play_arrow,
            kind: LzButtonKind.primary,
            autofocus: true,
            onPressed: () => _play(Duration(milliseconds: h!.positionMs)),
          ),
        LzButton(
          label: canResume ? 'Play from start' : 'Play',
          icon: canResume ? Icons.replay : Icons.play_arrow,
          kind: canResume ? LzButtonKind.secondary : LzButtonKind.primary,
          autofocus: !canResume,
          onPressed: () => _play(Duration.zero),
        ),
        LzButton(
          label: fav ? 'In favourites' : 'Add to favourites',
          icon: fav ? Icons.favorite : Icons.favorite_border,
          onPressed: () => app.toggleFavourite(ContentKind.movie, m.streamId),
        ),
      ],
    );
  }
}

/// Shared layout for movie and series details.
class DetailsFrame extends StatelessWidget {
  const DetailsFrame({
    super.key,
    required this.title,
    required this.kicker,
    required this.meta,
    required this.plot,
    required this.buttons,
    this.cast = '',
    this.backdrop,
    this.poster,
    this.bottom,
  });

  final String title;
  final String kicker;
  final String meta;
  final String plot;
  final String cast;
  final String? backdrop;
  final String? poster;
  final List<Widget> buttons;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final size = MediaQuery.sizeOf(context);
    return BackHandler(
      child: Scaffold(
        body: Stack(children: [
          if (backdrop != null && !compact)
            Positioned(
              top: 0,
              right: 0,
              width: size.width * 0.6,
              height: size.height * 0.62,
              child: Opacity(
                opacity: 0.55,
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.45],
                  ).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: LzImage(url: backdrop, label: title, radius: 0),
                ),
              ),
            ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 56, compact ? 8 : 44, compact ? 16 : 56, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (compact)
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back), tooltip: 'Back'),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (poster != null && !compact) ...[
                    SizedBox(width: 200, height: 300, child: LzImage(url: poster, label: title, radius: 14, showTitle: true)),
                    const SizedBox(width: 36),
                  ],
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(kicker, style: const TextStyle(fontSize: 15, color: LzColors.muted)),
                        const SizedBox(height: 10),
                        Text(title, style: headline(compact ? 30 : 48)),
                        const SizedBox(height: 12),
                        if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 15, color: LzColors.textSoft)),
                        if (plot.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(plot, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, height: 1.55, color: LzColors.textSoft)),
                        ],
                        if (cast.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Cast: $cast', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: LzColors.muted)),
                        ],
                        const SizedBox(height: 24),
                        FocusTraversalGroup(child: Wrap(spacing: 14, runSpacing: 12, children: buttons)),
                      ]),
                    ),
                  ),
                ]),
                if (bottom != null) ...[const SizedBox(height: 32), bottom!],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
