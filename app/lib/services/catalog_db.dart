import 'package:sqlite3/sqlite3.dart';

import '../models/models.dart';

/// Local SQLite store for every playlist's channels, films, series, guide,
/// favourites and watch history. Plain SQL so it needs no code generation.
class CatalogDb {
  CatalogDb._(this._db);
  final Database _db;

  static CatalogDb open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');
    db.execute('PRAGMA foreign_keys=ON;');
    final c = CatalogDb._(db);
    c._migrate();
    return c;
  }

  static CatalogDb memory() {
    final c = CatalogDb._(sqlite3.openInMemory());
    c._migrate();
    return c;
  }

  void close() => _db.dispose();

  void _migrate() {
    final v = _db.userVersion;
    if (v < 1) {
      _db.execute('''
CREATE TABLE IF NOT EXISTS playlists(
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
  url TEXT NOT NULL DEFAULT '', username TEXT NOT NULL DEFAULT '', password TEXT NOT NULL DEFAULT '',
  epg_url TEXT NOT NULL DEFAULT '', last_sync INTEGER);
CREATE TABLE IF NOT EXISTS categories(
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, cat_id TEXT NOT NULL, name TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(playlist_id, kind, cat_id));
CREATE TABLE IF NOT EXISTS channels(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  stream_id TEXT NOT NULL, num INTEGER NOT NULL, name TEXT NOT NULL, name_lc TEXT NOT NULL,
  logo TEXT, cat_id TEXT NOT NULL, epg_id TEXT NOT NULL DEFAULT '', url TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS ix_channels_cat ON channels(playlist_id, cat_id, num);
CREATE INDEX IF NOT EXISTS ix_channels_num ON channels(playlist_id, num);
CREATE TABLE IF NOT EXISTS movies(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  stream_id TEXT NOT NULL, name TEXT NOT NULL, name_lc TEXT NOT NULL, poster TEXT, cat_id TEXT NOT NULL,
  url TEXT NOT NULL, rating TEXT NOT NULL DEFAULT '', year TEXT NOT NULL DEFAULT '', added INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS ix_movies_cat ON movies(playlist_id, cat_id, added DESC);
CREATE TABLE IF NOT EXISTS series(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  series_id TEXT NOT NULL, name TEXT NOT NULL, name_lc TEXT NOT NULL, poster TEXT, cat_id TEXT NOT NULL,
  plot TEXT NOT NULL DEFAULT '', rating TEXT NOT NULL DEFAULT '', year TEXT NOT NULL DEFAULT '', added INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS ix_series_cat ON series(playlist_id, cat_id, added DESC);
CREATE TABLE IF NOT EXISTS episodes(
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  ep_id TEXT NOT NULL, series_id TEXT NOT NULL, season INTEGER NOT NULL, episode INTEGER NOT NULL,
  title TEXT NOT NULL, url TEXT NOT NULL, duration INTEGER NOT NULL DEFAULT 0, plot TEXT NOT NULL DEFAULT '', image TEXT,
  PRIMARY KEY(playlist_id, ep_id));
CREATE INDEX IF NOT EXISTS ix_episodes_series ON episodes(playlist_id, series_id, season, episode);
CREATE TABLE IF NOT EXISTS epg(
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  epg_id TEXT NOT NULL, start INTEGER NOT NULL, stop INTEGER NOT NULL, title TEXT NOT NULL, descr TEXT NOT NULL DEFAULT '');
CREATE INDEX IF NOT EXISTS ix_epg ON epg(playlist_id, epg_id, start);
CREATE TABLE IF NOT EXISTS favourites(
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, item_key TEXT NOT NULL, added INTEGER NOT NULL,
  PRIMARY KEY(playlist_id, kind, item_key));
CREATE TABLE IF NOT EXISTS history(
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, item_key TEXT NOT NULL, title TEXT NOT NULL, image TEXT,
  position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0,
  extra TEXT NOT NULL DEFAULT '', updated INTEGER NOT NULL,
  PRIMARY KEY(playlist_id, kind, item_key));
''');
      _db.userVersion = 1;
    }
  }

  // ---------------------------------------------------------------- playlists

  List<PlaylistSource> playlists() => _db
      .select('SELECT * FROM playlists ORDER BY id')
      .map((r) => PlaylistSource(
            id: r['id'] as int,
            name: r['name'] as String,
            type: SourceType.values.firstWhere((t) => t.name == r['type'], orElse: () => SourceType.m3uUrl),
            url: r['url'] as String,
            username: r['username'] as String,
            password: r['password'] as String,
            epgUrl: r['epg_url'] as String,
            lastSync: r['last_sync'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last_sync'] as int),
          ))
      .toList();

  int addPlaylist(PlaylistSource p) {
    _db.execute(
      'INSERT INTO playlists(name,type,url,username,password,epg_url) VALUES(?,?,?,?,?,?)',
      [p.name, p.type.name, p.url, p.username, p.password, p.epgUrl],
    );
    return _db.lastInsertRowId;
  }

  void updatePlaylistMeta(int id, {String? name, String? epgUrl, DateTime? lastSync}) {
    if (name != null) _db.execute('UPDATE playlists SET name=? WHERE id=?', [name, id]);
    if (epgUrl != null) _db.execute('UPDATE playlists SET epg_url=? WHERE id=?', [epgUrl, id]);
    if (lastSync != null) _db.execute('UPDATE playlists SET last_sync=? WHERE id=?', [lastSync.millisecondsSinceEpoch, id]);
  }

  void deletePlaylist(int id) => _db.execute('DELETE FROM playlists WHERE id=?', [id]);

  // ------------------------------------------------------------------- writes

  void transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Clears catalogue rows (not favourites / history) before a resync.
  void clearCatalogue(int pid) {
    for (final t in ['categories', 'channels', 'movies', 'series', 'episodes']) {
      _db.execute('DELETE FROM $t WHERE playlist_id=?', [pid]);
    }
  }

  void insertCategories(int pid, ContentKind kind, List<(String id, String name)> cats) {
    final st = _db.prepare('INSERT OR REPLACE INTO categories(playlist_id,kind,cat_id,name,sort) VALUES(?,?,?,?,?)');
    var i = 0;
    for (final c in cats) {
      st.execute([pid, kind.name, c.$1, c.$2, i++]);
    }
    st.dispose();
  }

  void insertChannels(int pid, Iterable<Map<String, Object?>> rows) {
    final st = _db.prepare('INSERT INTO channels(playlist_id,stream_id,num,name,name_lc,logo,cat_id,epg_id,url) VALUES(?,?,?,?,?,?,?,?,?)');
    for (final r in rows) {
      final name = r['name'] as String;
      st.execute([pid, r['stream_id'], r['num'], name, name.toLowerCase(), r['logo'], r['cat_id'], r['epg_id'] ?? '', r['url']]);
    }
    st.dispose();
  }

  void insertMovies(int pid, Iterable<Map<String, Object?>> rows) {
    final st = _db.prepare('INSERT INTO movies(playlist_id,stream_id,name,name_lc,poster,cat_id,url,rating,year,added) VALUES(?,?,?,?,?,?,?,?,?,?)');
    for (final r in rows) {
      final name = r['name'] as String;
      st.execute([pid, r['stream_id'], name, name.toLowerCase(), r['poster'], r['cat_id'], r['url'], r['rating'] ?? '', r['year'] ?? '', r['added'] ?? 0]);
    }
    st.dispose();
  }

  void insertSeries(int pid, Iterable<Map<String, Object?>> rows) {
    final st = _db.prepare('INSERT INTO series(playlist_id,series_id,name,name_lc,poster,cat_id,plot,rating,year,added) VALUES(?,?,?,?,?,?,?,?,?,?)');
    for (final r in rows) {
      final name = r['name'] as String;
      st.execute([pid, r['series_id'], name, name.toLowerCase(), r['poster'], r['cat_id'], r['plot'] ?? '', r['rating'] ?? '', r['year'] ?? '', r['added'] ?? 0]);
    }
    st.dispose();
  }

  void replaceEpisodes(int pid, String seriesId, List<Episode> eps) {
    transaction(() {
      _db.execute('DELETE FROM episodes WHERE playlist_id=? AND series_id=?', [pid, seriesId]);
      insertEpisodes(pid, eps);
    });
  }

  void insertEpisodes(int pid, List<Episode> eps) {
    final st = _db.prepare('INSERT OR REPLACE INTO episodes(playlist_id,ep_id,series_id,season,episode,title,url,duration,plot,image) VALUES(?,?,?,?,?,?,?,?,?,?)');
    for (final e in eps) {
      st.execute([pid, e.id, e.seriesId, e.season, e.episode, e.title, e.url, e.durationSecs, e.plot, e.image]);
    }
    st.dispose();
  }

  void clearEpg(int pid) => _db.execute('DELETE FROM epg WHERE playlist_id=?', [pid]);

  void insertEpg(int pid, Iterable<(String, int, int, String, String)> rows) {
    final st = _db.prepare('INSERT INTO epg(playlist_id,epg_id,start,stop,title,descr) VALUES(?,?,?,?,?,?)');
    for (final r in rows) {
      st.execute([pid, r.$1, r.$2, r.$3, r.$4, r.$5]);
    }
    st.dispose();
  }

  void pruneEpg(int pid, DateTime before) =>
      _db.execute('DELETE FROM epg WHERE playlist_id=? AND stop<?', [pid, before.millisecondsSinceEpoch]);

  bool hasEpg(int pid) => _db.select('SELECT 1 FROM epg WHERE playlist_id=? LIMIT 1', [pid]).isNotEmpty;

  // -------------------------------------------------------------------- reads

  List<Category> categories(int pid, ContentKind kind) {
    final table = switch (kind) { ContentKind.live => 'channels', ContentKind.movie => 'movies', ContentKind.series => 'series' };
    return _db
        .select(
          'SELECT c.cat_id, c.name, (SELECT COUNT(*) FROM $table t WHERE t.playlist_id=c.playlist_id AND t.cat_id=c.cat_id) AS n '
          'FROM categories c WHERE c.playlist_id=? AND c.kind=? ORDER BY c.sort',
          [pid, kind.name],
        )
        .map((r) => Category(id: r['cat_id'] as String, name: r['name'] as String, kind: kind, count: r['n'] as int))
        .where((c) => c.count > 0)
        .toList();
  }

  int count(int pid, ContentKind kind) {
    final table = switch (kind) { ContentKind.live => 'channels', ContentKind.movie => 'movies', ContentKind.series => 'series' };
    return _db.select('SELECT COUNT(*) AS n FROM $table WHERE playlist_id=?', [pid]).first['n'] as int;
  }

  Channel _channel(Row r) => Channel(
        id: r['id'] as int,
        streamId: r['stream_id'] as String,
        name: r['name'] as String,
        number: r['num'] as int,
        url: r['url'] as String,
        logo: r['logo'] as String?,
        categoryId: r['cat_id'] as String,
        epgId: r['epg_id'] as String,
      );

  Movie _movie(Row r) => Movie(
        id: r['id'] as int,
        streamId: r['stream_id'] as String,
        name: r['name'] as String,
        url: r['url'] as String,
        poster: r['poster'] as String?,
        categoryId: r['cat_id'] as String,
        rating: r['rating'] as String,
        year: r['year'] as String,
      );

  Series _series(Row r) => Series(
        id: r['id'] as int,
        seriesId: r['series_id'] as String,
        name: r['name'] as String,
        poster: r['poster'] as String?,
        categoryId: r['cat_id'] as String,
        plot: r['plot'] as String,
        rating: r['rating'] as String,
        year: r['year'] as String,
      );

  List<Channel> channels(int pid, String catId, {Set<String> hiddenCats = const {}}) {
    final List<Row> rows;
    if (catId == Category.allId) {
      rows = _db.select('SELECT * FROM channels WHERE playlist_id=? ORDER BY num', [pid]).toList();
    } else if (catId == Category.favId) {
      rows = _db.select(
        'SELECT c.* FROM channels c JOIN favourites f ON f.playlist_id=c.playlist_id AND f.kind=\'live\' AND f.item_key=c.stream_id '
        'WHERE c.playlist_id=? ORDER BY f.added',
        [pid],
      ).toList();
    } else if (catId == Category.recentId) {
      rows = _db.select(
        'SELECT c.* FROM channels c JOIN history h ON h.playlist_id=c.playlist_id AND h.kind=\'live\' AND h.item_key=c.stream_id '
        'WHERE c.playlist_id=? ORDER BY h.updated DESC LIMIT 50',
        [pid],
      ).toList();
    } else {
      rows = _db.select('SELECT * FROM channels WHERE playlist_id=? AND cat_id=? ORDER BY num', [pid, catId]).toList();
    }
    return rows.map(_channel).where((c) => !hiddenCats.contains(c.categoryId) || catId == c.categoryId).toList();
  }

  Channel? channelByNumber(int pid, int number) {
    final r = _db.select('SELECT * FROM channels WHERE playlist_id=? AND num=? LIMIT 1', [pid, number]);
    return r.isEmpty ? null : _channel(r.first);
  }

  Channel? channelByStream(int pid, String streamId) {
    final r = _db.select('SELECT * FROM channels WHERE playlist_id=? AND stream_id=? LIMIT 1', [pid, streamId]);
    return r.isEmpty ? null : _channel(r.first);
  }

  List<Movie> movies(int pid, String catId, {String sort = 'added'}) {
    final order = sort == 'name' ? 'name_lc' : 'added DESC, id';
    if (catId == Category.favId) {
      return _db
          .select(
              'SELECT m.* FROM movies m JOIN favourites f ON f.playlist_id=m.playlist_id AND f.kind=\'movie\' AND f.item_key=m.stream_id '
              'WHERE m.playlist_id=? ORDER BY f.added DESC',
              [pid])
          .map(_movie)
          .toList();
    }
    if (catId == Category.allId) {
      return _db.select('SELECT * FROM movies WHERE playlist_id=? ORDER BY $order LIMIT 2000', [pid]).map(_movie).toList();
    }
    return _db.select('SELECT * FROM movies WHERE playlist_id=? AND cat_id=? ORDER BY $order', [pid, catId]).map(_movie).toList();
  }

  Movie? movieByStream(int pid, String streamId) {
    final r = _db.select('SELECT * FROM movies WHERE playlist_id=? AND stream_id=? LIMIT 1', [pid, streamId]);
    return r.isEmpty ? null : _movie(r.first);
  }

  List<Series> seriesList(int pid, String catId, {String sort = 'added'}) {
    final order = sort == 'name' ? 'name_lc' : 'added DESC, id';
    if (catId == Category.favId) {
      return _db
          .select(
              'SELECT s.* FROM series s JOIN favourites f ON f.playlist_id=s.playlist_id AND f.kind=\'series\' AND f.item_key=s.series_id '
              'WHERE s.playlist_id=? ORDER BY f.added DESC',
              [pid])
          .map(_series)
          .toList();
    }
    if (catId == Category.allId) {
      return _db.select('SELECT * FROM series WHERE playlist_id=? ORDER BY $order LIMIT 2000', [pid]).map(_series).toList();
    }
    return _db.select('SELECT * FROM series WHERE playlist_id=? AND cat_id=? ORDER BY $order', [pid, catId]).map(_series).toList();
  }

  Series? seriesById(int pid, String seriesId) {
    final r = _db.select('SELECT * FROM series WHERE playlist_id=? AND series_id=? LIMIT 1', [pid, seriesId]);
    return r.isEmpty ? null : _series(r.first);
  }

  List<Episode> episodes(int pid, String seriesId) => _db
      .select('SELECT * FROM episodes WHERE playlist_id=? AND series_id=? ORDER BY season, episode', [pid, seriesId])
      .map((r) => Episode(
            id: r['ep_id'] as String,
            seriesId: r['series_id'] as String,
            season: r['season'] as int,
            episode: r['episode'] as int,
            title: r['title'] as String,
            url: r['url'] as String,
            durationSecs: r['duration'] as int,
            plot: r['plot'] as String,
            image: r['image'] as String?,
          ))
      .toList();

  List<Programme> programmes(int pid, String epgId, DateTime from, DateTime to) {
    if (epgId.isEmpty) return const [];
    return _db
        .select(
          'SELECT start, stop, title, descr FROM epg WHERE playlist_id=? AND epg_id=? AND stop>? AND start<? ORDER BY start',
          [pid, epgId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        )
        .map((r) => Programme(
              start: DateTime.fromMillisecondsSinceEpoch(r['start'] as int),
              stop: DateTime.fromMillisecondsSinceEpoch(r['stop'] as int),
              title: r['title'] as String,
              description: r['descr'] as String,
            ))
        .toList();
  }

  SearchResults search(int pid, String query, {Set<String> hiddenCats = const {}, int limit = 60}) {
    final q = '%${query.toLowerCase().replaceAll('%', '').replaceAll('_', r'\_')}%';
    final ch = _db
        .select("SELECT * FROM channels WHERE playlist_id=? AND name_lc LIKE ? ESCAPE '\\' ORDER BY num LIMIT ?", [pid, q, limit])
        .map(_channel)
        .where((c) => !hiddenCats.contains(c.categoryId))
        .toList();
    final mv = _db
        .select("SELECT * FROM movies WHERE playlist_id=? AND name_lc LIKE ? ESCAPE '\\' ORDER BY name_lc LIMIT ?", [pid, q, limit])
        .map(_movie)
        .where((m) => !hiddenCats.contains(m.categoryId))
        .toList();
    final se = _db
        .select("SELECT * FROM series WHERE playlist_id=? AND name_lc LIKE ? ESCAPE '\\' ORDER BY name_lc LIMIT ?", [pid, q, limit])
        .map(_series)
        .where((s) => !hiddenCats.contains(s.categoryId))
        .toList();
    return SearchResults(ch, mv, se);
  }

  // --------------------------------------------------------------- favourites

  bool isFavourite(int pid, ContentKind kind, String key) =>
      _db.select('SELECT 1 FROM favourites WHERE playlist_id=? AND kind=? AND item_key=?', [pid, kind.name, key]).isNotEmpty;

  bool toggleFavourite(int pid, ContentKind kind, String key) {
    if (isFavourite(pid, kind, key)) {
      _db.execute('DELETE FROM favourites WHERE playlist_id=? AND kind=? AND item_key=?', [pid, kind.name, key]);
      return false;
    }
    _db.execute('INSERT INTO favourites(playlist_id,kind,item_key,added) VALUES(?,?,?,?)',
        [pid, kind.name, key, DateTime.now().millisecondsSinceEpoch]);
    return true;
  }

  Set<String> favouriteKeys(int pid, ContentKind kind) =>
      _db.select('SELECT item_key FROM favourites WHERE playlist_id=? AND kind=?', [pid, kind.name]).map((r) => r['item_key'] as String).toSet();

  // ------------------------------------------------------------------ history

  void saveHistory(int pid, HistoryItem h) {
    _db.execute(
      'INSERT INTO history(playlist_id,kind,item_key,title,image,position_ms,duration_ms,extra,updated) VALUES(?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(playlist_id,kind,item_key) DO UPDATE SET title=excluded.title, image=excluded.image, position_ms=excluded.position_ms, '
      'duration_ms=excluded.duration_ms, extra=excluded.extra, updated=excluded.updated',
      [pid, h.kind, h.key, h.title, h.image, h.positionMs, h.durationMs, h.extra, h.updated.millisecondsSinceEpoch],
    );
  }

  HistoryItem? history(int pid, String kind, String key) {
    final r = _db.select('SELECT * FROM history WHERE playlist_id=? AND kind=? AND item_key=?', [pid, kind, key]);
    return r.isEmpty ? null : _hist(r.first);
  }

  /// Most recent first. For series, only the latest episode of each show.
  List<HistoryItem> recent(int pid, {int limit = 20}) {
    final rows = _db.select(
      "SELECT * FROM history WHERE playlist_id=? AND (kind='live' OR (duration_ms>0 AND position_ms < duration_ms*0.95)) "
      'ORDER BY updated DESC LIMIT ?',
      [pid, limit * 3],
    );
    final seen = <String>{};
    final out = <HistoryItem>[];
    for (final r in rows) {
      final h = _hist(r);
      final k = h.kind == 'episode' ? 'series:${h.extra}' : '${h.kind}:${h.key}';
      if (seen.add(k)) out.add(h);
      if (out.length >= limit) break;
    }
    return out;
  }

  void clearHistory(int pid) => _db.execute('DELETE FROM history WHERE playlist_id=?', [pid]);

  HistoryItem _hist(Row r) => HistoryItem(
        kind: r['kind'] as String,
        key: r['item_key'] as String,
        title: r['title'] as String,
        image: r['image'] as String?,
        positionMs: r['position_ms'] as int,
        durationMs: r['duration_ms'] as int,
        extra: r['extra'] as String,
        updated: DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
      );
}
