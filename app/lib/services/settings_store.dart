import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BufferSize { small, medium, large }

enum StreamFormat { ts, hls }

enum AspectMode { fit, fill, stretch }

/// User preferences, persisted with shared_preferences.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._p);
  final SharedPreferences _p;

  static Future<SettingsStore> load() async => SettingsStore(await SharedPreferences.getInstance());

  SharedPreferences get prefs => _p;

  // Playback
  BufferSize get buffer => BufferSize.values[(_p.getInt('buffer') ?? 1).clamp(0, 2)];
  set buffer(BufferSize v) => _setInt('buffer', v.index);

  /// Demuxer cache in bytes passed to libmpv.
  int get bufferBytes => switch (buffer) {
        BufferSize.small => 16 * 1024 * 1024,
        BufferSize.medium => 48 * 1024 * 1024,
        BufferSize.large => 128 * 1024 * 1024,
      };

  StreamFormat get streamFormat => StreamFormat.values[(_p.getInt('format') ?? 0).clamp(0, 1)];
  set streamFormat(StreamFormat v) => _setInt('format', v.index);

  AspectMode get aspect => AspectMode.values[(_p.getInt('aspect') ?? 0).clamp(0, 2)];
  set aspect(AspectMode v) => _setInt('aspect', v.index);

  bool get autoPlayNext => _p.getBool('autoNext') ?? true;
  set autoPlayNext(bool v) => _setBool('autoNext', v);

  // Appearance
  /// 'dark' or 'black' (pure black for OLED TVs).
  String get theme => _p.getString('theme') ?? 'dark';
  set theme(String v) => _setString('theme', v);

  String get language => _p.getString('language') ?? 'en';
  set language(String v) => _setString('language', v);

  // Parental control
  String get parentalPin => _p.getString('pin') ?? '';
  set parentalPin(String v) => _setString('pin', v);
  bool get hasPin => parentalPin.isNotEmpty;

  /// Locked categories as "playlistId:kind:categoryId".
  Set<String> get lockedCategories => (_p.getStringList('locked') ?? const []).toSet();
  bool isLocked(int pid, String kind, String catId) => lockedCategories.contains('$pid:$kind:$catId');
  void setLocked(int pid, String kind, String catId, bool locked) {
    final s = lockedCategories;
    final k = '$pid:$kind:$catId';
    locked ? s.add(k) : s.remove(k);
    _p.setStringList('locked', s.toList());
    notifyListeners();
  }

  Set<String> lockedFor(int pid, String kind) => lockedCategories
      .where((k) => k.startsWith('$pid:$kind:'))
      .map((k) => k.substring('$pid:$kind:'.length))
      .toSet();

  // Playlists
  int? get activePlaylistId => _p.getInt('activePlaylist');
  set activePlaylistId(int? v) {
    v == null ? _p.remove('activePlaylist') : _p.setInt('activePlaylist', v);
    notifyListeners();
  }

  DateTime? epgUpdated(int pid) {
    final v = _p.getInt('epg_$pid');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  void setEpgUpdated(int pid, DateTime t) => _p.setInt('epg_$pid', t.millisecondsSinceEpoch);

  void _setInt(String k, int v) {
    _p.setInt(k, v);
    notifyListeners();
  }

  void _setBool(String k, bool v) {
    _p.setBool(k, v);
    notifyListeners();
  }

  void _setString(String k, String v) {
    _p.setString(k, v);
    notifyListeners();
  }
}
