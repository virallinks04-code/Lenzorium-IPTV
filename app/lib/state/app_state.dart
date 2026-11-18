import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/catalog_db.dart';
import '../services/licence_service.dart';
import '../services/playlist_sync.dart';
import '../services/settings_store.dart';
import '../services/xtream_api.dart';

/// App-wide state: licence, playlists, catalogue access, favourites and
/// history. Screens read it with `context.watch<AppState>()`.
class AppState extends ChangeNotifier {
  AppState._(this.settings, this.licence, this.db) : _sync = PlaylistSync(db);

  final SettingsStore settings;
  final LicenceService licence;
  final CatalogDb db;
  final PlaylistSync _sync;

  static Future<AppState> create() async {
    final settings = await SettingsStore.load();
    final dir = await getApplicationSupportDirectory();
    final db = CatalogDb.open(p.join(dir.path, 'catalog.db'));
    final s = AppState._(settings, LicenceService(settings.prefs), db);
    s._reloadPlaylists();
    s.licenceState = s.licence.cached ?? LicenceState(status: LicenceStatus.unknown);
    return s;
  }

  LicenceState licenceState = LicenceState(status: LicenceStatus.unknown);

  List<PlaylistSource> playlists = [];
  PlaylistSource? active;
  int get pid => active?.id ?? -1;
  bool get hasPlaylist => active != null;

  bool syncing = false;
  String syncStep = '';
  String? syncError;

  /// Bumped whenever favourites or history change so lists can refresh.
  int revision = 0;

  AccountInfo? providerAccount;
  XtreamApi? _xtream;
  XtreamApi? get xtream => _xtream;

  Directory? _filesDir;

  void _reloadPlaylists() {
    playlists = db.playlists();
    final want = settings.activePlaylistId;
    active = playlists.where((x) => x.id == want).firstOrNull ?? playlists.firstOrNull;
    _xtream = active?.type == SourceType.xtream ? XtreamApi(active!.url, active!.username, active!.password) : null;
  }

  // ------------------------------------------------------------------ licence

  Future<void> checkLicence() async {
    final res = await licence.check();
    licenceState = res.state;
    notifyListeners();
    if (res.pushedPlaylists.isNotEmpty) {
      final done = <String>[];
      for (final (id, src) in res.pushedPlaylists) {
        try {
          await addPlaylist(src);
          done.add(id);
        } catch (_) {/* customer sees the error when they open it */}
      }
      await licence.ackPlaylists(done);
    }
  }

  // ---------------------------------------------------------------- playlists

  Future<Directory> filesDir() async => _filesDir ??= await getApplicationSupportDirectory();

  /// Adds a source, makes it active and loads it. Throws a readable
  /// message if it cannot be loaded (and removes it again).
  Future<void> addPlaylist(PlaylistSource src) async {
    final id = db.addPlaylist(src);
    settings.activePlaylistId = id;
    _reloadPlaylists();
    try {
      await resync();
      if (syncError != null) throw SyncException(syncError!);
    } catch (e) {
      db.deletePlaylist(id);
      _reloadPlaylists();
      settings.activePlaylistId = active?.id;
      notifyListeners();
      rethrow;
    }
  }

  void setActive(int id) {
    settings.activePlaylistId = id;
    _reloadPlaylists();
    providerAccount = null;
    revision++;
    notifyListeners();
    unawaited(_loadAccount());
    unawaited(refreshEpgIfStale());
  }

  void deletePlaylist(int id) {
    db.deletePlaylist(id);
    if (settings.activePlaylistId == id) settings.activePlaylistId = null;
    _reloadPlaylists();
    revision++;
    notifyListeners();
  }

  void renamePlaylist(int id, String name) {
    db.updatePlaylistMeta(id, name: name);
    _reloadPlaylists();
    notifyListeners();
  }

  Future<void> resync({bool withEpg = true}) async {
    final src = active;
    if (src == null || syncing) return;
    syncing = true;
    syncError = null;
    syncStep = 'Connecting…';
    notifyListeners();
    String epgUrl = '';
    try {
      epgUrl = await _sync.syncCatalogue(src, hls: settings.streamFormat == StreamFormat.hls, onStep: _step);
      _reloadPlaylists();
    } catch (e) {
      syncError = e.toString();
      syncing = false;
      notifyListeners();
      return;
    }
    revision++;
    syncing = false;
    notifyListeners();
    unawaited(_loadAccount());
    if (withEpg && epgUrl.isNotEmpty) unawaited(_syncEpg(src.id!, epgUrl));
  }

  bool epgSyncing = false;

  Future<void> _syncEpg(int id, String url) async {
    if (epgSyncing) return;
    epgSyncing = true;
    notifyListeners();
    try {
      await _sync.syncEpg(id, url);
      settings.setEpgUpdated(id, DateTime.now());
    } catch (e) {
      debugPrint('EPG sync failed: $e');
    } finally {
      epgSyncing = false;
      revision++;
      notifyListeners();
    }
  }

  /// The guide is refreshed once a day.
  Future<void> refreshEpgIfStale() async {
    final src = active;
    if (src == null || src.epgUrl.isEmpty) return;
    final last = settings.epgUpdated(src.id!);
    if (last == null || DateTime.now().difference(last) > const Duration(hours: 24) || !db.hasEpg(src.id!)) {
      db.pruneEpg(src.id!, DateTime.now().subtract(const Duration(hours: 12)));
      await _syncEpg(src.id!, src.epgUrl);
    }
  }

  Future<void> refreshEpgNow() async {
    final src = active;
    if (src == null || src.epgUrl.isEmpty) return;
    await _syncEpg(src.id!, src.epgUrl);
  }

  Future<void> _loadAccount() async {
    final x = _xtream;
    if (x == null) return;
    try {
      providerAccount = await x.account();
      notifyListeners();
    } catch (_) {}
  }

  void _step(String s) {
    syncStep = s;
    notifyListeners();
  }

  // ----------------------------------------------------------- guide (EPG)

  final Map<String, (DateTime, List<Programme>)> _shortEpgCache = {};

  /// Programmes for a channel from now on: XMLTV first, else the provider's
  /// short EPG (Xtream). Cached for five minutes.
  Future<List<Programme>> upcoming(Channel c, {int count = 3}) async {
    final now = DateTime.now();
    final local = db.programmes(pid, c.epgId, now, now.add(const Duration(hours: 12)));
    if (local.isNotEmpty) return local.take(count).toList();
    final x = _xtream;
    if (x == null) return const [];
    final cached = _shortEpgCache[c.streamId];
    if (cached != null && now.difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2.where((p) => p.stop.isAfter(now)).take(count).toList();
    }
    try {
      final list = await x.shortEpg(c.streamId, limit: count + 1);
      _shortEpgCache[c.streamId] = (now, list);
      return list.where((p) => p.stop.isAfter(now)).take(count).toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------- favourites / history

  bool isFavourite(ContentKind k, String key) => hasPlaylist && db.isFavourite(pid, k, key);

  bool toggleFavourite(ContentKind k, String key) {
    final r = db.toggleFavourite(pid, k, key);
    revision++;
    notifyListeners();
    return r;
  }

  void saveHistory(HistoryItem h, {bool notify = false}) {
    if (!hasPlaylist) return;
    db.saveHistory(pid, h);
    revision++;
    if (notify) notifyListeners();
  }

  void notifyHistory() => notifyListeners();

  Set<String> lockedCats(ContentKind k) => hasPlaylist ? settings.lockedFor(pid, k.name) : const {};
}
