import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import 'movie_details_screen.dart';
import 'search_screen.dart';
import 'series_details_screen.dart';

/// Poster grid by category, for Movies or Series.
class VodScreen extends StatefulWidget {
  const VodScreen({super.key, required this.kind, this.initialCategory = Category.allId});
  final ContentKind kind;
  final String initialCategory;
  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  late String _cat = widget.initialCategory;
  String _sort = 'added';
  final Set<String> _unlocked = {};

  bool get _movies => widget.kind == ContentKind.movie;

  Future<void> _pick(Category c) async {
    final app = context.read<AppState>();
    if (app.settings.isLocked(app.pid, widget.kind.name, c.id) && !_unlocked.contains(c.id)) {
      if (!await askPin(context)) return;
      _unlocked.add(c.id);
    }
    setState(() => _cat = c.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final compact = isCompact(context);
    final pid = app.pid;
    final locked = app.lockedCats(widget.kind).difference(_unlocked);
    final cats = [
      Category(id: Category.allId, name: _movies ? 'All movies' : 'All series', kind: widget.kind),
      Category(id: Category.favId, name: 'Favourites', kind: widget.kind),
      ...app.db.categories(pid, widget.kind),
    ];
    final current = cats.where((c) => c.id == _cat).firstOrNull ?? cats.first;

    final List<_PosterData> items;
    if (_movies) {
      items = app.db
          .movies(pid, _cat, sort: _sort)
          .where((m) => !locked.contains(m.categoryId) || _cat == m.categoryId)
          .map((m) {
        final h = app.db.history(pid, 'movie', m.streamId);
        return _PosterData(
          title: m.name,
          image: m.poster,
          meta: [m.year, m.rating.isNotEmpty && m.rating != '0' ? '★ ${m.rating}' : ''].where((s) => s.isNotEmpty).join(' · '),
          progress: h?.progress ?? 0,
          open: () => push(context, MovieDetailsScreen(movie: m)),
          favKey: m.streamId,
        );
      }).toList();
    } else {
      items = app.db
          .seriesList(pid, _cat, sort: _sort)
          .where((s) => !locked.contains(s.categoryId) || _cat == s.categoryId)
          .map((s) => _PosterData(
                title: s.name,
                image: s.poster,
                meta: [s.year, s.rating.isNotEmpty && s.rating != '0' ? '★ ${s.rating}' : ''].where((x) => x.isNotEmpty).join(' · '),
                open: () => push(context, SeriesDetailsScreen(series: s)),
                favKey: s.seriesId,
              ))
          .toList();
    }

    final grid = items.isEmpty
        ? EmptyState(_cat == Category.favId ? 'No favourites yet.\nPress the menu key (or F) on a poster to add it.' : 'Nothing here yet.')
        : GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: compact ? 140 : 180,
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 0.56,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _Poster(
              data: items[i],
              autofocus: i == 0,
              onMenu: () {
                final added = app.toggleFavourite(widget.kind, items[i].favKey);
                toast(context, added ? 'Added to favourites' : 'Removed from favourites');
              },
            ),
          );

    return ScreenFrame(
      title: _movies ? 'Movies' : 'Series',
      subtitle: '${current.name} · ${items.length} ${_movies ? 'titles' : 'shows'}',
      actions: [
        LzButton(label: 'Search', icon: Icons.search, height: 44, onPressed: () => push(context, const SearchScreen())),
        LzButton(
          label: _sort == 'added' ? 'Sort: Recently added' : 'Sort: A–Z',
          height: 44,
          onPressed: () => setState(() => _sort = _sort == 'added' ? 'name' : 'added'),
        ),
      ],
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => MenuRow(label: cats[i].name, selected: cats[i].id == _cat, onSelect: () => _pick(cats[i])),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: grid),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 220,
                child: FocusTraversalGroup(
                  child: ListView.builder(
                    itemCount: cats.length,
                    itemBuilder: (_, i) {
                      final c = cats[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: MenuRow(
                          label: c.name,
                          icon: app.settings.isLocked(pid, widget.kind.name, c.id) ? Icons.lock_outline : null,
                          trailing: c.count > 0 ? '${c.count}' : null,
                          selected: c.id == _cat,
                          onSelect: () => _pick(c),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: FocusTraversalGroup(child: grid)),
            ]),
    );
  }
}

class _PosterData {
  _PosterData({required this.title, required this.image, required this.meta, required this.open, required this.favKey, this.progress = 0});
  final String title;
  final String? image;
  final String meta;
  final double progress;
  final VoidCallback open;
  final String favKey;
}

class _Poster extends StatelessWidget {
  const _Poster({required this.data, this.autofocus = false, required this.onMenu});
  final _PosterData data;
  final bool autofocus;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        onSelect: data.open,
        onMenu: onMenu,
        radius: 12,
        scaleOnFocus: 1.04,
        semanticLabel: data.title,
        builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              LzImage(url: data.image, label: data.title, radius: 12, showTitle: true),
              if (data.progress > 0.01)
                Positioned(left: 0, right: 0, bottom: 0, child: ProgressBar(data.progress, color: Colors.white, track: Colors.black45)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(data.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(data.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: LzColors.muted)),
        ]),
      );
}
