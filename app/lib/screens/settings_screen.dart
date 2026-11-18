import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/licence_service.dart';
import '../services/settings_store.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';
import 'activate_screen.dart';
import 'add_playlist_screen.dart';

enum _Section { playlists, parental, language, appearance, playback, licence, about }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _sec = _Section.playlists;

  static const _labels = {
    _Section.playlists: 'Playlists',
    _Section.parental: 'Parental control',
    _Section.language: 'Language',
    _Section.appearance: 'Appearance',
    _Section.playback: 'Playback',
    _Section.licence: 'Licence',
    _Section.about: 'About',
  };

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final menu = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in _Section.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: MenuRow(
            label: _labels[s]!,
            selected: s == _sec,
            autofocus: s == _Section.playlists,
            onSelect: () => setState(() => _sec = s),
            onFocus: compact ? null : () => setState(() => _sec = s),
          ),
        ),
      const Spacer(),
      const Text('${AppConfig.appName} ${AppConfig.version}\nby ${AppConfig.company}', style: TextStyle(fontSize: 13, height: 1.6, color: LzColors.faint)),
    ]);
    final body = SingleChildScrollView(child: _section(context));
    return ScreenFrame(
      title: 'Settings',
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in _Section.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(width: 160, child: MenuRow(label: _labels[s]!, selected: s == _sec, onSelect: () => setState(() => _sec = s))),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Expanded(child: body),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 280, child: FocusTraversalGroup(child: menu)),
              const SizedBox(width: 48),
              Expanded(child: FocusTraversalGroup(child: body)),
            ]),
    );
  }

  Widget _section(BuildContext context) => switch (_sec) {
        _Section.playlists => const _Playlists(),
        _Section.parental => const _Parental(),
        _Section.language => const _Language(),
        _Section.appearance => const _Appearance(),
        _Section.playback => const _Playback(),
        _Section.licence => const _Licence(),
        _Section.about => const _About(),
      };
}

// ------------------------------------------------------------------ shared

class _Head extends StatelessWidget {
  const _Head(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20, top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: headline(26)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 16, color: LzColors.muted)),
        ]),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.trailing});
  final String title;
  final String? subtitle;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(color: LzColors.surface, border: Border.all(color: LzColors.line), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(fontSize: 15, color: LzColors.muted))],
            ]),
          ),
          const SizedBox(width: 16),
          trailing,
        ]),
      );
}

/// Segmented choice that works with the D-pad.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.values, required this.labels, required this.selected, required this.onChanged});
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: LzColors.bg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < values.length; i++)
            Focusable(
              radius: 9,
              onSelect: () => onChanged(values[i]),
              semanticLabel: labels[i],
              builder: (_, f) => Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: values[i] == selected ? LzColors.accent : (f ? LzColors.surface2 : Colors.transparent),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: values[i] == selected ? FontWeight.w600 : FontWeight.w400,
                      color: values[i] == selected ? Colors.white : LzColors.textSoft,
                    )),
              ),
            ),
        ]),
      );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Focusable(
        radius: 999,
        onSelect: () => onChanged(!value),
        semanticLabel: '$label ${value ? 'on' : 'off'}',
        builder: (_, __) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 60,
          height: 34,
          padding: const EdgeInsets.all(4),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(color: value ? LzColors.accent : LzColors.surface3, borderRadius: BorderRadius.circular(17)),
          child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      );
}

// --------------------------------------------------------------- sections

class _Playlists extends StatelessWidget {
  const _Playlists();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Playlists', 'Your M3U playlists and Xtream Codes logins. Switch between them in one tap from Home.'),
      if (app.syncing) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(app.syncStep, style: const TextStyle(color: LzColors.textSoft))),
      if (app.syncError != null)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(app.syncError!, style: const TextStyle(color: Color(0xFFFF8A8A)))),
      for (final p in app.playlists)
        _Card(
          title: p.name + (p.id == app.pid ? '  ·  Active' : ''),
          subtitle: [
            switch (p.type) { SourceType.xtream => 'Xtream Codes', SourceType.m3uUrl => 'M3U link', SourceType.m3uFile => 'M3U file' },
            if (p.lastSync != null) 'updated ${dateLong(p.lastSync!)} ${hm(p.lastSync!)}',
            if (p.epgUrl.isNotEmpty) 'guide ${app.settings.epgUpdated(p.id!) == null ? 'not loaded' : 'updated ${hm(app.settings.epgUpdated(p.id!)!)}'}',
          ].join('  ·  '),
          trailing: Wrap(spacing: 10, children: [
            if (p.id != app.pid) LzButton(label: 'Use', height: 44, onPressed: () => app.setActive(p.id!)),
            if (p.id == app.pid) LzButton(label: 'Refresh', icon: Icons.refresh, height: 44, onPressed: app.syncing ? null : () => app.resync()),
            if (p.id == app.pid && p.epgUrl.isNotEmpty) LzButton(label: 'Refresh guide', height: 44, onPressed: app.epgSyncing ? null : () => app.refreshEpgNow()),
            LzButton(
              label: 'Remove',
              kind: LzButtonKind.ghost,
              height: 44,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Remove ${p.name}?'),
                    content: const Text('Its favourites and watch history on this device are removed too.'),
                    actions: [
                      LzButton(label: 'Cancel', autofocus: true, onPressed: () => Navigator.of(ctx).pop(false)),
                      LzButton(label: 'Remove', kind: LzButtonKind.primary, onPressed: () => Navigator.of(ctx).pop(true)),
                    ],
                  ),
                );
                if (ok == true) app.deletePlaylist(p.id!);
              },
            ),
          ]),
        ),
      const SizedBox(height: 6),
      LzButton(label: 'Add playlist', icon: Icons.add, kind: LzButtonKind.primary, onPressed: () => push(context, const AddPlaylistScreen())),
    ]);
  }
}

class _Parental extends StatelessWidget {
  const _Parental();

  Future<void> _setPin(BuildContext context) async {
    final s = context.read<SettingsStore>();
    if (s.hasPin && !await askPin(context, title: 'Enter current PIN')) return;
    if (!context.mounted) return;
    final a = await showDialog<String>(context: context, builder: (_) => const PinDialog(title: 'New 4-digit PIN'));
    if (a == null || !context.mounted) return;
    final b = await showDialog<String>(context: context, builder: (_) => const PinDialog(title: 'Enter it again'));
    if (!context.mounted) return;
    if (a != b) {
      toast(context, 'The PINs did not match. Nothing changed.');
      return;
    }
    s.parentalPin = a;
    toast(context, 'Parental PIN saved');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final groups = [
      ('Live TV', ContentKind.live),
      ('Movies', ContentKind.movie),
      ('Series', ContentKind.series),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Parental control', 'Lock categories behind a 4-digit PIN. Locked categories are hidden from lists and search until unlocked.'),
      _Card(
        title: s.hasPin ? 'PIN is set' : 'No PIN set',
        subtitle: s.hasPin ? 'Needed to open locked categories and change these settings' : 'Set a PIN first, then choose categories to lock',
        trailing: Wrap(spacing: 10, children: [
          LzButton(label: s.hasPin ? 'Change PIN' : 'Set PIN', height: 44, onPressed: () => _setPin(context)),
          if (s.hasPin)
            LzButton(
              label: 'Remove PIN',
              kind: LzButtonKind.ghost,
              height: 44,
              onPressed: () async {
                if (await askPin(context)) s.parentalPin = '';
              },
            ),
        ]),
      ),
      if (s.hasPin && app.hasPlaylist)
        for (final (label, kind) in groups) ...[
          Padding(padding: const EdgeInsets.only(top: 10, bottom: 10), child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in app.db.categories(app.pid, kind))
              Focusable(
                radius: 10,
                onSelect: () async {
                  if (!await askPin(context)) return;
                  s.setLocked(app.pid, kind.name, c.id, !s.isLocked(app.pid, kind.name, c.id));
                },
                builder: (_, f) {
                  final locked = s.isLocked(app.pid, kind.name, c.id);
                  return Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: locked ? LzColors.surface3 : (f ? LzColors.surface2 : LzColors.surface),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(locked ? Icons.lock : Icons.lock_open, size: 16, color: locked ? LzColors.amber : LzColors.muted),
                      const SizedBox(width: 8),
                      Text(c.name, style: const TextStyle(fontSize: 15)),
                    ]),
                  );
                },
              ),
          ]),
        ],
    ]);
  }
}

class _Language extends StatelessWidget {
  const _Language();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Language', 'Language of the app’s menus. Audio and subtitle languages are chosen in the player.'),
      _Card(
        title: 'App language',
        trailing: _Segmented<String>(values: const ['en'], labels: const ['English (UK)'], selected: s.language, onChanged: (v) => s.language = v),
      ),
    ]);
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Appearance', 'How Lenzorium looks on this device.'),
      _Card(
        title: 'Theme',
        subtitle: 'Black saves power and looks deeper on OLED TVs',
        trailing: _Segmented<String>(values: const ['dark', 'black'], labels: const ['Dark', 'Black'], selected: s.theme, onChanged: (v) => s.theme = v),
      ),
    ]);
  }
}

class _Playback extends StatelessWidget {
  const _Playback();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final app = context.read<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Playback', 'How streams load and play on this device.'),
      _Card(
        title: 'Buffer size',
        subtitle: 'Larger is smoother on weak Wi-Fi, but uses more memory',
        trailing: _Segmented<BufferSize>(
          values: BufferSize.values,
          labels: const ['Small', 'Medium', 'Large'],
          selected: s.buffer,
          onChanged: (v) => s.buffer = v,
        ),
      ),
      _Card(
        title: 'Stream format',
        subtitle: 'For Xtream Codes live channels. Try HLS if channels stutter',
        trailing: _Segmented<StreamFormat>(
          values: StreamFormat.values,
          labels: const ['MPEG-TS', 'HLS'],
          selected: s.streamFormat,
          onChanged: (v) {
            if (v == s.streamFormat) return;
            s.streamFormat = v;
            if (app.active?.type == SourceType.xtream) app.resync(withEpg: false);
          },
        ),
      ),
      _Card(
        title: 'Default aspect ratio',
        subtitle: 'Can also be changed during playback',
        trailing: _Segmented<AspectMode>(
          values: AspectMode.values,
          labels: const ['Fit', 'Fill', 'Stretch'],
          selected: s.aspect,
          onChanged: (v) => s.aspect = v,
        ),
      ),
      _Card(
        title: 'Auto-play next episode',
        subtitle: 'Starts the next episode when one finishes',
        trailing: _Switch(label: 'Auto-play next episode', value: s.autoPlayNext, onChanged: (v) => s.autoPlayNext = v),
      ),
      _Card(
        title: 'Watch history',
        subtitle: 'Recently watched and resume points for this playlist',
        trailing: LzButton(
          label: 'Clear',
          height: 44,
          onPressed: () {
            app.db.clearHistory(app.pid);
            app.notifyHistory();
            toast(context, 'Watch history cleared');
          },
        ),
      ),
    ]);
  }
}

class _Licence extends StatelessWidget {
  const _Licence();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.licenceState;
    final status = switch (l.status) {
      LicenceStatus.active => l.plan == 'lifetime' || l.expiresAt == null ? 'Activated · Lifetime' : 'Activated until ${dateLong(l.expiresAt!)}',
      LicenceStatus.trial => 'Free trial · ${l.trialDaysLeft} days left',
      LicenceStatus.expired => 'Expired',
      LicenceStatus.unknown => 'Not checked yet',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('Licence', 'Your Lenzorium activation for this device.'),
      _Card(
        title: status,
        subtitle: 'Device ID ${app.licence.deviceId}${l.offline ? '  ·  offline' : ''}',
        trailing: LzButton(label: 'Activation details', height: 44, onPressed: () => push(context, const ActivateScreen(fromSettings: true))),
      ),
    ]);
  }
}

class _About extends StatelessWidget {
  const _About();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Head('About', ''),
      const Row(children: [LzLogo(size: 56), SizedBox(width: 18)]),
      const SizedBox(height: 14),
      Text(AppConfig.appName, style: headline(28)),
      const Text('Version ${AppConfig.version} · by ${AppConfig.company}', style: TextStyle(fontSize: 16, color: LzColors.muted)),
      const SizedBox(height: 20),
      const Text(AppConfig.contentNotice, style: TextStyle(fontSize: 16, height: 1.5)),
      const SizedBox(height: 14),
      const Text(
        'Privacy: your playlists, logins, favourites and watch history stay on this device. '
        'The Lenzorium licence server only stores this device’s ID, your email and your payment reference.',
        style: TextStyle(fontSize: 15, height: 1.5, color: LzColors.muted),
      ),
      const SizedBox(height: 14),
      Text('Device ID ${app.licence.deviceId}', style: const TextStyle(fontSize: 15, color: LzColors.muted)),
      const SizedBox(height: 6),
      const Text('Video playback uses libmpv via media_kit (LGPL).', style: TextStyle(fontSize: 13, color: LzColors.faint)),
    ]);
  }
}
