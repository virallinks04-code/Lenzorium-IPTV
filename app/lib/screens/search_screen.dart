import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import '../widgets/tv_text_field.dart';
import 'movie_details_screen.dart';
import 'player_screen.dart';
import 'series_details_screen.dart';

/// One search across channels, movies and series.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  SearchResults? _res;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final app = context.read<AppState>();
      final q = v.trim();
      setState(() {
        _res = q.length < 2
            ? null
            : app.db.search(app.pid, q,
                hiddenCats: {...app.lockedCats(ContentKind.live), ...app.lockedCats(ContentKind.movie), ...app.lockedCats(ContentKind.series)});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return ScreenFrame(
      title: 'Search',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: TvTextField(
            controller: _q,
            label: 'Channels, movies and series',
            autofocus: true,
            prefixIcon: Icons.search,
            onChanged: _changed,
            onSubmitted: _changed,
            textInputAction: TextInputAction.search,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: res == null
              ? const EmptyState('Type at least two letters.', icon: Icons.search)
              : res.isEmpty
                  ? const EmptyState('Nothing found.')
                  : ListView(children: [
                      if (res.channels.isNotEmpty) _Row(title: 'Channels', children: [
                        for (final c in res.channels)
                          _ResultCard(
                            title: c.name,
                            subtitle: 'Channel ${c.number}',
                            image: c.logo,
                            wide: true,
                            onTap: () async {
                              final pb = context.read<PlaybackController>();
                              final list = res.channels;
                              await pb.start(list.map(PlayItem.live).toList(), list.indexOf(c));
                              if (context.mounted) push(context, const PlayerScreen());
                            },
                          ),
                      ]),
                      if (res.movies.isNotEmpty) _Row(title: 'Movies', children: [
                        for (final m in res.movies)
                          _ResultCard(title: m.name, subtitle: m.year, image: m.poster, onTap: () => push(context, MovieDetailsScreen(movie: m))),
                      ]),
                      if (res.series.isNotEmpty) _Row(title: 'Series', children: [
                        for (final s in res.series)
                          _ResultCard(title: s.name, subtitle: s.year, image: s.poster, onTap: () => push(context, SeriesDetailsScreen(series: s))),
                      ]),
                    ]),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title · ${children.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 230,
            child: FocusTraversalGroup(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => children[i],
              ),
            ),
          ),
        ]),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.subtitle, required this.image, required this.onTap, this.wide = false});
  final String title;
  final String subtitle;
  final String? image;
  final VoidCallback onTap;
  final bool wide;
  @override
  Widget build(BuildContext context) => Focusable(
        onSelect: onTap,
        radius: 12,
        semanticLabel: title,
        builder: (_, __) => SizedBox(
          width: wide ? 200 : 130,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(
                color: wide ? LzColors.surface : null,
                padding: wide ? const EdgeInsets.all(24) : null,
                child: LzImage(url: image, label: title, radius: 12, fit: wide ? BoxFit.contain : BoxFit.cover, showTitle: !wide, monogramSize: 22),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(subtitle, maxLines: 1, style: const TextStyle(fontSize: 13, color: LzColors.muted)),
          ]),
        ),
      );
}
