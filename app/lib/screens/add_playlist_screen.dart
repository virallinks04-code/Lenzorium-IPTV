import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/config.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/focusable.dart';
import '../widgets/tv_text_field.dart';
import 'home_screen.dart';

/// Add a source: M3U link, M3U file or Xtream Codes login. The QR code
/// lets the customer type it on their phone instead of with the remote.
class AddPlaylistScreen extends StatefulWidget {
  const AddPlaylistScreen({super.key, this.firstRun = false});
  final bool firstRun;
  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  SourceType _tab = SourceType.xtream;
  final _name = TextEditingController(text: 'Home');
  final _url = TextEditingController();
  final _server = TextEditingController(text: AppConfig.defaultXtreamServer);
  bool get _serverLocked => AppConfig.lockXtreamServer && AppConfig.defaultXtreamServer.isNotEmpty;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _epg = TextEditingController();
  String? _filePath;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  int _knownPlaylists = 0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _knownPlaylists = app.playlists.length;
    if (app.playlists.isNotEmpty) _name.text = 'Playlist ${app.playlists.length + 1}';
    // A playlist entered on the website arrives with the licence check.
    _poll = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (_busy) return;
      await app.checkLicence();
      if (mounted && app.playlists.length > _knownPlaylists) _done();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_name, _url, _server, _user, _pass, _epg]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() => _filePath = path);
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final name = _name.text.trim().isEmpty ? 'Playlist' : _name.text.trim();
    PlaylistSource src;
    switch (_tab) {
      case SourceType.m3uUrl:
        if (!_url.text.trim().startsWith('http')) return _fail('Enter the full playlist link, starting with http:// or https://');
        src = PlaylistSource(name: name, type: SourceType.m3uUrl, url: _url.text.trim(), epgUrl: _epg.text.trim());
      case SourceType.m3uFile:
        if (_filePath == null) return _fail('Choose a playlist file first.');
        final dir = Directory(p.join((await app.filesDir()).path, 'playlists'));
        await dir.create(recursive: true);
        final copy = await File(_filePath!).copy(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.m3u'));
        src = PlaylistSource(name: name, type: SourceType.m3uFile, url: copy.path, epgUrl: _epg.text.trim());
      case SourceType.xtream:
        if (_server.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
          return _fail('Enter the server, username and password from your provider.');
        }
        src = PlaylistSource(
          name: name,
          type: SourceType.xtream,
          url: _server.text.trim(),
          username: _user.text.trim(),
          password: _pass.text,
          epgUrl: _epg.text.trim(),
        );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.addPlaylist(src);
      if (!mounted) return;
      _done();
    } catch (e) {
      _fail(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String msg) => setState(() => _error = msg);

  void _done() {
    _poll?.cancel();
    if (widget.firstRun) {
      replaceAll(context, const HomeScreen());
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final compact = isCompact(context);

    final form = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.firstRun)
        const Text('STEP 2 OF 2', style: TextStyle(fontSize: 15, color: LzColors.accentText, fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 8),
      Text('Add your playlist', style: headline(compact ? 30 : 40)),
      const SizedBox(height: 8),
      const Text('Use the details your TV provider gave you. You only do this once.',
          style: TextStyle(fontSize: 17, color: LzColors.muted)),
      const SizedBox(height: 24),
      if (!_serverLocked) Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: LzColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Wrap(spacing: 6, children: [
          _Tab('M3U link', _tab == SourceType.m3uUrl, () => setState(() => _tab = SourceType.m3uUrl)),
          _Tab('M3U file', _tab == SourceType.m3uFile, () => setState(() => _tab = SourceType.m3uFile)),
          _Tab('Xtream Codes login', _tab == SourceType.xtream, () => setState(() => _tab = SourceType.xtream)),
        ]),
      ),
      const SizedBox(height: 22),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(children: [
          TvTextField(controller: _name, label: 'Playlist name'),
          const SizedBox(height: 16),
          ...switch (_tab) {
            SourceType.m3uUrl => [
                TvTextField(controller: _url, label: 'Playlist link (M3U URL)', hint: 'http://provider.example/get.php?…', keyboardType: TextInputType.url),
              ],
            SourceType.m3uFile => [
                Row(children: [
                  LzButton(label: 'Choose file', icon: Icons.folder_open, onPressed: _pickFile),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(_filePath == null ? 'No file chosen' : p.basename(_filePath!),
                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: LzColors.muted, fontSize: 16)),
                  ),
                ]),
              ],
            SourceType.xtream => [
                if (!_serverLocked) ...[
                  TvTextField(controller: _server, label: 'Server URL', hint: 'http://provider.example:8080', keyboardType: TextInputType.url),
                  const SizedBox(height: 16),
                ],
                TvTextField(controller: _user, label: 'Username'),
                const SizedBox(height: 16),
                TvTextField(controller: _pass, label: 'Password', obscure: true, textInputAction: TextInputAction.done, onSubmitted: (_) => _submit()),
              ],
          },
          const SizedBox(height: 16),
          TvTextField(
            controller: _epg,
            label: 'TV guide link (optional)',
            hint: _tab == SourceType.xtream ? 'Leave empty to use the provider’s guide' : 'XMLTV link, if not in the playlist',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
          ),
        ]),
      ),
      const SizedBox(height: 22),
      if (_error != null) ...[
        Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 16)),
        const SizedBox(height: 14),
      ],
      if (_busy) ...[
        Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 14),
          Text(app.syncStep, style: const TextStyle(fontSize: 16, color: LzColors.textSoft)),
        ]),
        const SizedBox(height: 14),
      ],
      Wrap(spacing: 16, runSpacing: 12, children: [
        LzButton(label: 'Add playlist', kind: LzButtonKind.primary, onPressed: _busy ? null : _submit),
        if (!widget.firstRun) LzButton(label: 'Back', kind: LzButtonKind.ghost, onPressed: () => Navigator.of(context).maybePop()),
      ]),
      const SizedBox(height: 28),
      const ContentNotice(),
    ]);

    final phone = Container(
      width: 360,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: LzColors.surface,
        border: Border.all(color: LzColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.smartphone, size: 36, color: LzColors.text),
        const SizedBox(height: 14),
        Text('Easier on your phone', style: headline(22), textAlign: TextAlign.center),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: QrImageView(data: app.licence.setupUrl, size: 180, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text('Scan, then type or paste your playlist on your phone. It appears here automatically.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.5, color: LzColors.muted)),
      ]),
    );

    return BackHandler(
      onBack: widget.firstRun ? () {} : null,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 72, vertical: compact ? 20 : 48),
            child: compact
                ? form
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: FocusTraversalGroup(child: form)),
                    const SizedBox(width: 64),
                    // On a TV the phone route is the friendly one.
                    if (!Platform.isWindows) phone,
                  ]),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Focusable(
        onSelect: onTap,
        radius: 10,
        builder: (_, focused) => Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? LzColors.surface3 : (focused ? LzColors.surface2 : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? LzColors.text : LzColors.muted,
              )),
        ),
      );
}
