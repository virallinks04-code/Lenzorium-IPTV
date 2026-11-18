import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/settings_store.dart';
import '../state/app_state.dart';
import '../state/playback.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/focusable.dart';

/// Full-screen player. Overlay: channel or title, programme, progress,
/// audio, subtitles, aspect, speed (films and series), favourite and
/// mini-player / picture-in-picture.
///
/// Remote with the overlay hidden: ▲▼ or CH+/− change channel, ◀ last
/// channel (live) or −10 s, ▶ +10 s, digits jump to a channel number,
/// OK shows the overlay, Back leaves.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, this.keepPlayingOnExit = false});
  final bool keepPlayingOnExit;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Panel { none, audio, subtitles, speed }

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlaybackController _pb = context.read<PlaybackController>();
  late final AppState _app = context.read<AppState>();
  final _rootFocus = FocusNode(debugLabel: 'player-root');
  final _firstControl = FocusNode(debugLabel: 'player-first-control');
  final List<StreamSubscription> _subs = [];

  bool _overlay = true;
  _Panel _panel = _Panel.none;
  Timer? _hide;
  Timer? _progressSave;
  Timer? _numberTimer;
  String _number = '';
  bool _buffering = false;
  String? _error;
  int _retries = 0;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = true;
  double _rate = 1;
  String? _lastKey;
  List<Programme> _epg = const [];
  bool _exiting = false;
  bool _pipSupported = false;

  Player get _player => _pb.player;
  PlayItem? get _item => _pb.current;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_pb.mini) WidgetsBinding.instance.addPostFrameCallback((_) => _pb.setMini(false));
    _subs.addAll([
      _player.stream.position.listen((p) => _pos = p),
      _player.stream.duration.listen((d) => setState(() => _dur = d)),
      _player.stream.playing.listen((v) => setState(() => _playing = v)),
      _player.stream.buffering.listen((b) {
        setState(() => _buffering = b);
        if (!b) _retries = 0;
      }),
      _player.stream.error.listen(_onError),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.rate.listen((r) => setState(() => _rate = r)),
    ]);
    _pb.addListener(_onItemChanged);
    _onItemChanged();
    _progressSave = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _bumpOverlay();
    _pb.pipSupported().then((v) {
      if (mounted) setState(() => _pipSupported = v);
    });
    // Repaint the seek bar once a second.
    _subs.add(Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted && _overlay) setState(() {});
    }));
  }

  @override
  void dispose() {
    _saveProgress();
    for (final s in _subs) {
      s.cancel();
    }
    _hide?.cancel();
    _progressSave?.cancel();
    _numberTimer?.cancel();
    _pb.removeListener(_onItemChanged);
    _rootFocus.dispose();
    _firstControl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_pb.mini && !widget.keepPlayingOnExit) unawaited(_pb.stop());
    super.dispose();
  }

  // ------------------------------------------------------------ item change

  void _onItemChanged() {
    final it = _item;
    if (it == null) {
      if (!_exiting && mounted && !_pb.mini) {
        _exiting = true;
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (it.key == _lastKey) return;
    _saveProgress();
    _lastKey = it.key;
    _error = null;
    _retries = 0;
    _epg = const [];
    if (it.isLive) {
      _app.saveHistory(HistoryItem(kind: 'live', key: it.key, title: it.title, image: it.image, updated: DateTime.now()));
      final ch = it.channel;
      if (ch != null) {
        _app.upcoming(ch, count: 2).then((l) {
          if (mounted && _lastKey == it.key) setState(() => _epg = l);
        });
      }
    }
    _bumpOverlay();
    if (mounted) setState(() {});
  }

  void _saveProgress() {
    final it = _item;
    if (it == null || it.isLive) return;
    final dur = _dur.inMilliseconds;
    if (dur <= 0) return;
    _app.saveHistory(HistoryItem(
      kind: it.kind,
      key: it.key,
      title: it.kind == 'episode' ? '${it.seriesTitle} · ${it.episode?.code ?? ''}' : it.title,
      image: it.image,
      positionMs: _pos.inMilliseconds,
      durationMs: dur,
      extra: it.seriesId,
      updated: DateTime.now(),
    ));
  }

  // ----------------------------------------------------- errors, auto-next

  void _onError(String e) {
    final it = _item;
    if (it == null) return;
    debugPrint('player error: $e');
    if (_retries < 5) {
      _retries++;
      setState(() => _error = 'Reconnecting…');
      Future.delayed(Duration(seconds: 2 * _retries), () {
        if (mounted && _item?.key == it.key) {
          _pb.reopen();
        }
      });
    } else {
      setState(() => _error = 'This stream is not available right now. Try another channel or check your provider.');
      _showOverlay();
    }
  }

  void _onCompleted() {
    final it = _item;
    if (it == null) return;
    if (it.isLive) {
      // A live stream should never end: the connection dropped.
      _onError('live stream ended');
      return;
    }
    if (it.kind == 'episode' && _app.settings.autoPlayNext && _pb.index < _pb.queue.length - 1) {
      _saveProgress();
      _pb.next();
      return;
    }
    Navigator.of(context).maybePop();
  }

  // --------------------------------------------------------------- overlay

  void _bumpOverlay() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted && _panel == _Panel.none && _error == null) {
        setState(() => _overlay = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _showOverlay() {
    if (!_overlay) {
      setState(() => _overlay = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstControl.requestFocus());
    }
    _bumpOverlay();
  }

  void _hideOverlay() {
    setState(() {
      _overlay = false;
      _panel = _Panel.none;
    });
    _rootFocus.requestFocus();
  }

  // ------------------------------------------------------------------ keys

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final it = _item;
    if (it == null) return KeyEventResult.ignored;

    // Always active.
    if (k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.pageUp) {
      if (it.isLive) _pb.prev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.pageDown) {
      if (it.isLive) _pb.next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause) {
      _player.playOrPause();
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    final digit = _digitOf(k);
    if (digit != null && it.isLive) {
      _typeDigit(digit);
      return KeyEventResult.handled;
    }

    if (_isBack(k)) {
      if (_panel != _Panel.none) {
        setState(() => _panel = _Panel.none);
        return KeyEventResult.handled;
      }
      if (_overlay) {
        _hideOverlay();
        return KeyEventResult.handled;
      }
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    if (_overlay) {
      _bumpOverlay();
      return KeyEventResult.ignored; // let the D-pad move between controls
    }

    // Overlay hidden.
    if (k == LogicalKeyboardKey.arrowUp && it.isLive) {
      _pb.prev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && it.isLive) {
      _pb.next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (it.isLive) {
        _pb.lastChannel();
      } else {
        _seekBy(-10);
        _showOverlay();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (!it.isLive) {
        _seekBy(10);
        _showOverlay();
      }
      return KeyEventResult.handled;
    }
    if (isSelectKey(k) || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (isMenuKey(k)) {
      _toggleFavourite();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isBack(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.browserBack || k == LogicalKeyboardKey.backspace;

  int? _digitOf(LogicalKeyboardKey k) {
    const digits = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    final a = digits.indexOf(k);
    if (a >= 0) return a;
    final b = numpad.indexOf(k);
    return b >= 0 ? b : null;
  }

  void _typeDigit(int d) {
    setState(() => _number = (_number + '$d').substring(0, (_number.length + 1).clamp(0, 5)));
    _numberTimer?.cancel();
    _numberTimer = Timer(const Duration(milliseconds: 1500), _goToNumber);
  }

  Future<void> _goToNumber() async {
    final n = int.tryParse(_number);
    setState(() => _number = '');
    if (n == null) return;
    final i = _pb.queue.indexWhere((q) => q.channel?.number == n);
    if (i >= 0) {
      await _pb.jump(i);
      return;
    }
    final ch = _app.db.channelByNumber(_app.pid, n);
    if (ch == null) {
      if (mounted) toast(context, 'No channel $n');
      return;
    }
    final all = _app.db.channels(_app.pid, Category.allId, hiddenCats: _app.lockedCats(ContentKind.live));
    final at = all.indexWhere((c) => c.id == ch.id);
    if (at < 0) {
      if (mounted) toast(context, 'Channel $n is locked');
      return;
    }
    await _pb.replaceAndPlay(all.map(PlayItem.live).toList(), at);
  }

  void _seekBy(int seconds) {
    if (_dur == Duration.zero) return;
    var t = _pos + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > _dur) t = _dur - const Duration(seconds: 1);
    _player.seek(t);
  }

  void _toggleFavourite() {
    final it = _item;
    if (it == null) return;
    final kind = switch (it.kind) { 'live' => ContentKind.live, 'movie' => ContentKind.movie, _ => ContentKind.series };
    final key = it.kind == 'episode' ? it.seriesId : it.key;
    final added = _app.toggleFavourite(kind, key);
    toast(context, added ? 'Added to favourites' : 'Removed from favourites');
    setState(() {});
  }

  void _cycleAspect() {
    final s = _app.settings;
    s.aspect = AspectMode.values[(s.aspect.index + 1) % AspectMode.values.length];
    setState(() {});
  }

  void _mini() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _pb.setMini(true);
      Navigator.of(context).maybePop();
    } else {
      _pb.enterPip();
    }
  }

  BoxFit get _fit => switch (_app.settings.aspect) {
        AspectMode.fit => BoxFit.contain,
        AspectMode.fill => BoxFit.cover,
        AspectMode.stretch => BoxFit.fill,
      };

  String get _aspectLabel => switch (_app.settings.aspect) {
        AspectMode.fit => 'Fit',
        AspectMode.fill => 'Fill',
        AspectMode.stretch => 'Stretch',
      };

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    context.watch<PlaybackController>();
    final it = _item;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _overlay ? _hideOverlay() : _showOverlay(),
          child: Stack(fit: StackFit.expand, children: [
            Video(controller: _pb.video, controls: NoVideoControls, fit: _fit, fill: Colors.black),
            if (_buffering || _error != null)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error == null || _error == 'Reconnecting…') const CircularProgressIndicator(color: Colors.white),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                    ),
                  ],
                ]),
              ),
            if (_number.isNotEmpty)
              Positioned(
                top: 36,
                right: 48,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Text(_number, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700)),
                ),
              ),
            if (it != null)
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(ignoring: !_overlay, child: _buildOverlay(it)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildOverlay(PlayItem it) {
    final compact = isCompact(context);
    final now = DateTime.now();
    final prog = _epg.where((p) => p.isOnAt(now)).firstOrNull;
    final next = _epg.where((p) => p.start.isAfter(now)).firstOrNull;
    final fav = _app.isFavourite(
      it.isLive ? ContentKind.live : (it.kind == 'movie' ? ContentKind.movie : ContentKind.series),
      it.kind == 'episode' ? it.seriesId : it.key,
    );
    final pad = compact ? 16.0 : 48.0;

    final controls = <Widget>[
      if (!it.isLive)
        _Ctl(icon: _playing ? Icons.pause : Icons.play_arrow, label: _playing ? 'Pause' : 'Play', focusNode: _firstControl, onTap: _player.playOrPause),
      if (!it.isLive) _Ctl(icon: Icons.replay_10, label: 'Back 10 s', onTap: () => _seekBy(-10)),
      if (!it.isLive) _Ctl(icon: Icons.forward_10, label: 'Forward 10 s', onTap: () => _seekBy(10)),
      _Ctl(
        label: 'Audio',
        icon: Icons.audiotrack,
        focusNode: it.isLive ? _firstControl : null,
        text: 'Audio · ${_trackName(_player.state.track.audio.title, _player.state.track.audio.language, _player.state.track.audio.id)}',
        onTap: () => setState(() => _panel = _panel == _Panel.audio ? _Panel.none : _Panel.audio),
      ),
      _Ctl(
        label: 'Subtitles',
        icon: Icons.subtitles_outlined,
        text: 'Subtitles · ${_player.state.track.subtitle.id == 'no' ? 'Off' : _trackName(_player.state.track.subtitle.title, _player.state.track.subtitle.language, _player.state.track.subtitle.id)}',
        onTap: () => setState(() => _panel = _panel == _Panel.subtitles ? _Panel.none : _Panel.subtitles),
      ),
      _Ctl(label: 'Aspect', icon: Icons.aspect_ratio, text: 'Aspect · $_aspectLabel', onTap: _cycleAspect),
      if (!it.isLive)
        _Ctl(label: 'Speed', icon: Icons.speed, text: '${_rate == 1 ? '1' : _rate.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}×', onTap: () => setState(() => _panel = _panel == _Panel.speed ? _Panel.none : _Panel.speed)),
      if (it.kind == 'episode' && _pb.index < _pb.queue.length - 1)
        _Ctl(label: 'Next episode', icon: Icons.skip_next, text: 'Next episode', onTap: () {
          _saveProgress();
          _pb.next();
        }),
      _Ctl(label: fav ? 'Remove favourite' : 'Add favourite', icon: fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? LzColors.amber : null, onTap: _toggleFavourite),
      if (!Platform.isAndroid || _pipSupported)
        _Ctl(label: Platform.isAndroid ? 'Picture-in-picture' : 'Mini player', icon: Icons.picture_in_picture_alt_outlined, onTap: _mini),
    ];

    return Stack(children: [
      const Positioned(left: 0, right: 0, top: 0, height: 170, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xC0000000), Colors.transparent])))),
      const Positioned(left: 0, right: 0, bottom: 0, height: 300, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xD8000000), Colors.transparent])))),
      // Top: channel or title.
      Positioned(
        top: compact ? 16 : 36,
        left: pad,
        right: pad,
        child: Row(children: [
          if (compact)
            IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back), tooltip: 'Back'),
          if (it.isLive) ...[
            Text(it.subtitle, style: headline(compact ? 24 : 34)),
            const SizedBox(width: 16),
            SizedBox(width: 60, height: 40, child: LzImage(url: it.image, label: it.title, fit: BoxFit.contain)),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.isLive ? it.title : (it.kind == 'episode' ? it.seriesTitle : it.title),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 18 : 22, fontWeight: FontWeight.w600)),
              if (it.kind == 'episode')
                Text('${it.episode?.code ?? ''} · ${it.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: LzColors.textSoft)),
            ]),
          ),
          if (it.isLive && !compact) const Text('CH ▲▼ to change · ◀ last channel', style: TextStyle(fontSize: 15, color: LzColors.textSoft)),
          if (!compact) ...[const SizedBox(width: 18), const Clock()],
        ]),
      ),
      // Bottom: programme / progress and controls.
      Positioned(
        left: pad,
        right: _panel == _Panel.none ? pad : (compact ? pad : 400),
        bottom: compact ? 16 : 40,
        child: FocusTraversalGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (it.isLive) ...[
              const Text('NOW', style: TextStyle(fontSize: 14, letterSpacing: 1, color: LzColors.textSoft)),
              Text(prog?.title ?? 'No guide information', style: headline(compact ? 22 : 32)),
              if (next != null) Text('Next at ${hm(next.start)} · ${next.title}', style: const TextStyle(fontSize: 16, color: LzColors.textSoft)),
              const SizedBox(height: 12),
              if (prog != null)
                Row(children: [
                  Text(hm(prog.start)),
                  const SizedBox(width: 14),
                  Expanded(child: ProgressBar(prog.progressAt(now), height: 6, color: LzColors.accent, track: Colors.white24)),
                  const SizedBox(width: 14),
                  Text(hm(prog.stop)),
                ]),
            ] else
              Row(children: [
                Text(durationText(_pos)),
                const SizedBox(width: 14),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 5, activeTrackColor: LzColors.accent, inactiveTrackColor: Colors.white24, thumbColor: Colors.white),
                    child: Slider(
                      value: _dur.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0),
                      onChanged: (v) => _player.seek(Duration(milliseconds: (v * _dur.inMilliseconds).round())),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(durationText(_dur)),
              ]),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: controls),
          ]),
        ),
      ),
      if (_panel != _Panel.none)
        Positioned(
          top: compact ? 70 : 120,
          right: compact ? 12 : 40,
          bottom: compact ? 12 : 40,
          width: 320,
          child: FocusTraversalGroup(child: _buildPanel()),
        ),
    ]);
  }

  String _trackName(String? title, String? lang, String id) {
    if (id == 'auto') return 'Auto';
    if (id == 'no') return 'Off';
    final parts = [if (lang != null && lang.isNotEmpty) lang.toUpperCase(), if (title != null && title.isNotEmpty) title];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  Widget _buildPanel() {
    final tracks = _player.state.tracks;
    final current = _player.state.track;
    final List<(String, bool, VoidCallback)> rows;
    final String title;
    switch (_panel) {
      case _Panel.audio:
        title = 'Audio track';
        rows = tracks.audio
            .where((t) => t.id != 'no')
            .map((t) => (_trackName(t.title, t.language, t.id), t.id == current.audio.id, () => _player.setAudioTrack(t)))
            .toList();
      case _Panel.subtitles:
        title = 'Subtitles';
        rows = [
          ('Off', current.subtitle.id == 'no', () => _player.setSubtitleTrack(SubtitleTrack.no())),
          ...tracks.subtitle
              .where((t) => t.id != 'no' && t.id != 'auto')
              .map((t) => (_trackName(t.title, t.language, t.id), t.id == current.subtitle.id, () => _player.setSubtitleTrack(t))),
        ];
      case _Panel.speed:
        title = 'Playback speed';
        rows = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((r) => ('${r}×', (_rate - r).abs() < 0.01, () => _player.setRate(r))).toList();
      case _Panel.none:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xEB0E1117), border: Border.all(color: LzColors.line), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title.toUpperCase(), style: const TextStyle(fontSize: 14, letterSpacing: 1.1, color: LzColors.muted)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(children: [
            for (final (i, r) in rows.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: MenuRow(
                  label: r.$1,
                  selected: r.$2,
                  autofocus: r.$2 || (i == 0 && !rows.any((x) => x.$2)),
                  trailing: r.$2 ? '✓' : null,
                  onSelect: () {
                    r.$3();
                    setState(() => _panel = _Panel.none);
                    _bumpOverlay();
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Ctl extends StatelessWidget {
  const _Ctl({required this.label, required this.icon, required this.onTap, this.text, this.focusNode, this.color});
  final String label;
  final IconData icon;
  final String? text;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final Color? color;

  @override
  Widget build(BuildContext context) => Focusable(
        focusNode: focusNode,
        onSelect: onTap,
        radius: 10,
        semanticLabel: label,
        builder: (_, f) => Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: text == null ? 12 : 16),
          decoration: BoxDecoration(color: f ? Colors.white30 : Colors.white12, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: color ?? Colors.white),
            if (text != null) ...[const SizedBox(width: 8), Text(text!, style: const TextStyle(fontSize: 15))],
          ]),
        ),
      );
}
