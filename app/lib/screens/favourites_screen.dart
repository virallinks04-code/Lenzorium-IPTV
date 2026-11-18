import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import 'live_tv_screen.dart';
import 'vod_screen.dart';

/// Shortcut to the favourite lists of each section.
class FavouritesScreen extends StatelessWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final live = app.db.favouriteKeys(app.pid, ContentKind.live).length;
    final movies = app.db.favouriteKeys(app.pid, ContentKind.movie).length;
    final series = app.db.favouriteKeys(app.pid, ContentKind.series).length;
    return ScreenFrame(
      title: 'Favourites',
      subtitle: 'Press the menu key (or F, or long-press) on any channel or poster to add it',
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(spacing: 18, runSpacing: 18, children: [
          _Big(label: 'Channels', count: live, icon: Icons.live_tv_rounded, autofocus: true,
              onTap: () => push(context, const LiveTvScreen(initialCategory: Category.favId))),
          _Big(label: 'Movies', count: movies, icon: Icons.movie_outlined, onTap: () => push(context, const _FavVod(kind: ContentKind.movie))),
          _Big(label: 'Series', count: series, icon: Icons.video_library_outlined, onTap: () => push(context, const _FavVod(kind: ContentKind.series))),
          _Big(label: 'Recently watched', count: null, icon: Icons.history, onTap: () => push(context, const LiveTvScreen(initialCategory: Category.recentId))),
        ]),
      ),
    );
  }
}

class _FavVod extends StatelessWidget {
  const _FavVod({required this.kind});
  final ContentKind kind;
  @override
  Widget build(BuildContext context) => VodScreen(kind: kind, initialCategory: Category.favId);
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.count, required this.icon, required this.onTap, this.autofocus = false});
  final String label;
  final int? count;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => LzButton(
        label: count == null ? label : '$label · $count',
        icon: icon,
        height: 88,
        autofocus: autofocus,
        onPressed: onTap,
      );
}
