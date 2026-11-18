import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/models.dart';
import '../services/settings_store.dart';

/// One thing to play: a live channel, a film or an episode.
class PlayItem {
  PlayItem({
    required this.kind,
    required this.key,
    required this.title,
    required this.url,
    this.subtitle = '',
    this.image,
    this.startAt = Duration.zero,
    this.channel,
    this.episode,
    this.seriesId = '',
    this.seriesTitle = '',
  });

  /// 'live', 'movie' or 'episode' (matches the history table).
  final String kind;
  final String key;
  final String title;
  final String url;
  final String subtitle;
  final String? image;
  final Duration startAt;
  final Channel? channel;
  final Episode? episode;
  final String seriesId;
  final String seriesTitle;

  bool get isLive => kind == 'live';

  static PlayItem live(Channel c) => PlayItem(
      kind: 'live', key: c.streamId, title: c.name, subtitle: '${c.number}', url: c.url, image: c.logo, channel: c);

  static PlayItem movie(Movie m, {Duration startAt = Duration.zero}) =>
      PlayItem(kind: 'movie', key: m.streamId, title: m.name, url: m.url, image: m.poster, startAt: startAt);

  static PlayItem ep(Series s, Episode e, {Duration startAt = Duration.zero}) => PlayItem(
        kind: 'episode',
        key: e.id,
        title: e.title,
        subtitle: '${s.name} · ${e.code}',
        url: e.url,
        image: e.image ?? s.poster,
        startAt: startAt,
        episode: e,
        seriesId: s.seriesId,
        seriesTitle: s.name,
      );
}

/// Holds the single libmpv player so playback can continue in the
/// mini-player (Windows) or picture-in-picture (Android phones).
class PlaybackController extends ChangeNotifier {
  PlaybackController(this.settings);
  final SettingsStore settings;

  Player? _player;
  VideoController? _video;
  int _bufferBytes = 0;

  List<PlayItem> queue = const [];
  int index = 0;
  int? previousIndex;
  bool mini = false;

  PlayItem? get current => queue.isEmpty ? null : queue[index.clamp(0, queue.length - 1)];
  bool get isActive => _player != null && queue.isNotEmpty;

  Player get player {
    _ensure();
    return _player!;
  }

  VideoController get video {
    _ensure();
    return _video!;
  }

  void _ensure() {
    final want = settings.bufferBytes;
    if (_player != null && _bufferBytes == want) return;
    _player?.dispose();
    _player = Player(configuration: PlayerConfiguration(bufferSize: want, title: 'Lenzorium Player'));
    _video = VideoController(_player!);
    _bufferBytes = want;
    final native = _player!.platform;
    if (native is NativePlayer) {
      // Faster live start and automatic reconnect inside libmpv.
      native.setProperty('network-timeout', '15');
      native.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      native.setProperty('cache', 'yes');
      native.setProperty('demuxer-readahead-secs', '20');
    }
  }

  Future<void> start(List<PlayItem> items, int at) async {
    queue = items;
    previousIndex = null;
    index = at;
    mini = false;
    await _openCurrent();
  }

  Future<void> jump(int to) async {
    if (queue.isEmpty) return;
    final n = (to % queue.length + queue.length) % queue.length;
    if (n == index) return;
    previousIndex = index;
    index = n;
    await _openCurrent();
  }

  Future<void> next() => jump(index + 1);
  Future<void> prev() => jump(index - 1);

  Future<void> lastChannel() async {
    if (previousIndex != null) await jump(previousIndex!);
  }

  Future<void> replaceAndPlay(List<PlayItem> items, int at) async {
    previousIndex = null;
    queue = items;
    index = at;
    await _openCurrent();
  }

  Future<void> reopen() => _openCurrent();

  Future<void> _openCurrent() async {
    final item = current;
    if (item == null) return;
    await player.open(Media(item.url, start: item.startAt > Duration.zero ? item.startAt : null), play: true);
    notifyListeners();
  }

  void setMini(bool v) {
    mini = v;
    notifyListeners();
  }

  Future<void> stop() async {
    mini = false;
    queue = const [];
    await _player?.stop();
    notifyListeners();
  }

  // Android picture-in-picture (implemented in MainActivity.kt).
  static const _pip = MethodChannel('lenzorium/pip');

  Future<bool> enterPip() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _pip.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pipSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _pip.invokeMethod<bool>('supported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
