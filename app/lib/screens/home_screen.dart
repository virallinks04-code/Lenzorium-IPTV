import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/licence_service.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import 'activate_screen.dart';
import 'add_playlist_screen.dart';
import 'favourites_screen.dart';
import 'guide_screen.dart';
import 'live_tv_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'series_details_screen.dart';
import 'settings_screen.dart';
import 'vod_screen.dart';
import 'movie_details_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final compact = isCompact(context);
    if (!app.licenceState.canWatch && app.licenceState.status != LicenceStatus.unknown) {
      return const ActivateScreen();
    }
    final pid = app.pid;
    final counts = app.hasPlaylist
        ? (app.db.count(pid, ContentKind.live), app.db.count(pid, ContentKind.movie), app.db.count(pid, ContentKind.series))
        : (0, 0, 0);
    final recent = app.hasPlaylist ? app.db.recent(pid, limit: 12) : <HistoryItem>[];

    String expiry() {
      final l = app.licenceState;
      final parts = <String>[];
      if (l.status == LicenceStatus.trial) parts.add('Trial · ${l.trialDaysLeft} days left');
      if (l.status == LicenceStatus.active) {
        parts.add(l.plan == 'lifetime' || l.expiresAt == null ? 'Licence: lifetime' : 'Licence until ${dateLong(l.expiresAt!)}');
      }
      final acc = app.providerAccount?.expires;
      if (acc != null) parts.add('Account expires ${dateLong(acc)}');
      return parts.join('  ·  ');
    }

    final tiles = <Widget>[
      _Tile(
        big: true,
        autofocus: true,
        icon: Icons.live_tv_rounded,
        title: 'Live TV',
        subtitle: '${_n(counts.$1)} channels',
        onTap: () => push(context, const LiveTvScreen()),
      ),
      _Tile(icon: Icons.movie_outlined, title: 'Movies', subtitle: '${_n(counts.$2)} titles', onTap: () => push(context, const VodScreen(kind: ContentKind.movie))),
      _Tile(icon: Icons.video_library_outlined, title: 'Series', subtitle: '${_n(counts.$3)} shows', onTap: () => push(context, const VodScreen(kind: ContentKind.series))),
    ];
    final small = <Widget>[
      _SmallTile(icon: Icons.calendar_view_week_outlined, title: 'TV guide', onTap: () => push(context, const GuideScreen())),
      _SmallTile(icon: Icons.search, title: 'Search', onTap: () => push(context, const SearchScreen())),
      _SmallTile(icon: Icons.favorite_border, title: 'Favourites', onTap: () => push(context, const FavouritesScreen())),
      _SmallTile(icon: Icons.settings_outlined, title: 'Settings', onTap: () => push(context, const SettingsScreen())),
    ];

    return BackHandler(
      onBack: () {},
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 56, vertical: compact ? 16 : 36),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              BrandBar(
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _PlaylistSwitcher(app: app),
                  if (!compact) ...[
                    const SizedBox(width: 20),
                    Text(expiry(), style: const TextStyle(fontSize: 15, color: LzColors.muted)),
                    const SizedBox(width: 20),
                    const Clock(),
                  ],
                ]),
              ),
              if (app.syncing || app.syncError != null) ...[
                const SizedBox(height: 16),
                _SyncBanner(app: app),
              ],
              SizedBox(height: compact ? 18 : 28),
              if (compact) ...[
                SizedBox(height: 180, child: tiles[0]),
                const SizedBox(height: 14),
                SizedBox(height: 150, child: Row(children: [Expanded(child: tiles[1]), const SizedBox(width: 14), Expanded(child: tiles[2])])),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: small,
                ),
              ] else ...[
                SizedBox(
                  height: 270,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 2, child: tiles[0]),
                    const SizedBox(width: 18),
                    Expanded(child: tiles[1]),
                    const SizedBox(width: 18),
                    Expanded(child: tiles[2]),
                  ]),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 100,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < small.length; i++) ...[
                      if (i > 0) const SizedBox(width: 18),
                      Expanded(child: small[i]),
                    ],
                  ]),
                ),
              ],
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 28),
                const Text('Continue watching', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => _RecentCard(item: recent[i]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  static String _n(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.big = false, this.autofocus = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool big;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        onSelect: onTap,
        radius: 22,
        scaleOnFocus: 1.02,
        semanticLabel: title,
        builder: (_, focused) => Container(
          padding: EdgeInsets.all(big ? 30 : 26),
          decoration: BoxDecoration(
            color: big ? LzColors.accent : (focused ? LzColors.surface2 : LzColors.surface),
            border: big ? null : Border.all(color: LzColors.line),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: big ? 52 : 42, color: Colors.white),
            const Spacer(),
            Text(title, style: headline(big ? 38 : 28).copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 16, color: big ? Colors.white.withOpacity(0.9) : LzColors.muted)),
          ]),
        ),
      );
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
        onSelect: onTap,
        radius: 18,
        semanticLabel: title,
        builder: (_, focused) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: focused ? LzColors.surface2 : LzColors.surface,
            border: Border.all(color: LzColors.line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item});
  final HistoryItem item;

  Future<void> _open(BuildContext context) async {
    final app = context.read<AppState>();
    final pid = app.pid;
    switch (item.kind) {
      case 'live':
        final c = app.db.channelByStream(pid, item.key);
        if (c == null) return;
        final list = app.db.channels(pid, c.categoryId);
        await context.read<PlaybackController>().start(list.map(PlayItem.live).toList(), list.indexWhere((x) => x.id == c.id).clamp(0, list.length));
        if (context.mounted) push(context, const PlayerScreen());
      case 'movie':
        final m = app.db.movieByStream(pid, item.key);
        if (m != null) push(context, MovieDetailsScreen(movie: m));
      case 'episode':
        final s = app.db.seriesById(pid, item.extra);
        if (s != null) push(context, SeriesDetailsScreen(series: s));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = item.kind == 'live' ? 'Live' : minutesLeft(item.positionMs, item.durationMs);
    return Focusable(
      onSelect: () => _open(context),
      radius: 14,
      builder: (_, __) => SizedBox(
        width: 220,
        child: Stack(fit: StackFit.expand, children: [
          LzImage(url: item.image, label: item.title, radius: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 13, color: Color(0xFFD6DAE3))),
            ]),
          ),
          if (item.kind != 'live')
            Positioned(left: 0, right: 0, bottom: 0, child: ProgressBar(item.progress, color: Colors.white, track: Colors.black45)),
        ]),
      ),
    );
  }
}

class _PlaylistSwitcher extends StatelessWidget {
  const _PlaylistSwitcher({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final name = app.active?.name ?? 'No playlist';
    return Focusable(
      radius: 999,
      onSelect: () => _open(context),
      semanticLabel: 'Switch playlist, current $name',
      builder: (_, focused) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: focused ? LzColors.surface2 : LzColors.surface,
          border: Border.all(color: LzColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 12, backgroundColor: LzColors.surface3, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 12, color: LzColors.text))),
          const SizedBox(width: 10),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
          const Icon(Icons.expand_more, size: 18, color: LzColors.muted),
        ]),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Playlists'),
        children: [
          for (final p in app.playlists)
            MenuRow(
              label: p.name,
              trailing: p.id == app.pid ? 'Active' : null,
              selected: p.id == app.pid,
              autofocus: p.id == app.pid,
              onSelect: () => Navigator.of(ctx).pop(p.id),
            ),
          MenuRow(label: 'Add playlist', icon: Icons.add, selected: false, onSelect: () => Navigator.of(ctx).pop(-1)),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked == -1) {
      push(context, const AddPlaylistScreen());
    } else if (picked != app.pid) {
      app.setActive(picked);
    }
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: LzColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          if (app.syncing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else const Icon(Icons.error_outline, color: Color(0xFFFF8A8A)),
          const SizedBox(width: 12),
          Expanded(child: Text(app.syncing ? app.syncStep : 'Could not update the playlist: ${app.syncError}', style: const TextStyle(fontSize: 15))),
          if (!app.syncing) LzButton(label: 'Try again', height: 44, onPressed: () => app.resync()),
        ]),
      );
}
