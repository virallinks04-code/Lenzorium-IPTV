import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'catalog_db.dart';
import 'm3u_parser.dart';
import 'xmltv_parser.dart';
import 'xtream_api.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads a playlist source and stores it in the local catalogue.
class PlaylistSync {
  PlaylistSync(this.db, {http.Client? client}) : _client = client ?? http.Client();
  final CatalogDb db;
  final http.Client _client;

  /// Loads channels, films and series. Returns the guide URL to use.
  Future<String> syncCatalogue(PlaylistSource p, {required bool hls, void Function(String step)? onStep}) async {
    final pid = p.id!;
    switch (p.type) {
      case SourceType.m3uUrl:
      case SourceType.m3uFile:
        onStep?.call('Downloading playlist…');
        final text = await _readM3u(p);
        onStep?.call('Reading channels…');
        final result = await Isolate.run(() => M3uParser.parse(text));
        if (result.entries.isEmpty) throw SyncException('No channels were found in this playlist.');
        onStep?.call('Saving ${result.entries.length} items…');
        db.transaction(() {
          db.clearCatalogue(pid);
          _storeM3u(pid, result.entries);
        });
        final epg = p.epgUrl.isNotEmpty ? p.epgUrl : result.epgUrl;
        db.updatePlaylistMeta(pid, epgUrl: epg, lastSync: DateTime.now());
        return epg;

      case SourceType.xtream:
        final api = XtreamApi(p.url, p.username, p.password, client: _client);
        onStep?.call('Signing in…');
        final acc = await api.account();
        if (acc.status.isNotEmpty && acc.status.toLowerCase() != 'active') {
          throw SyncException('Your provider account is ${acc.status.toLowerCase()}.');
        }
        onStep?.call('Loading live channels…');
        final liveCats = await api.liveCategories();
        final live = await api.liveStreams();
        onStep?.call('Loading movies…');
        final vodCats = await api.vodCategories();
        final vod = await api.vodStreams();
        onStep?.call('Loading series…');
        final serCats = await api.seriesCategories();
        final ser = await api.seriesList();
        onStep?.call('Saving ${live.length + vod.length + ser.length} items…');
        db.transaction(() {
          db.clearCatalogue(pid);
          _storeXtream(pid, api, hls, liveCats, live, vodCats, vod, serCats, ser);
        });
        final epg = p.epgUrl.isNotEmpty ? p.epgUrl : api.xmltvUrl();
        db.updatePlaylistMeta(pid, epgUrl: epg, lastSync: DateTime.now());
        return epg;
    }
  }

  Future<String> _readM3u(PlaylistSource p) async {
    if (p.type == SourceType.m3uFile) {
      final f = File(p.url);
      if (!await f.exists()) throw SyncException('The playlist file is missing. Add it again.');
      return utf8.decode(await f.readAsBytes(), allowMalformed: true);
    }
    final uri = Uri.tryParse(p.url.trim());
    if (uri == null || !uri.hasScheme) throw SyncException('That playlist link is not valid.');
    final http.Response res;
    try {
      res = await _client.get(uri, headers: {'User-Agent': 'LenzoriumPlayer/1.0'}).timeout(const Duration(seconds: 90));
    } catch (_) {
      throw SyncException('Could not download the playlist. Check the link and your connection.');
    }
    if (res.statusCode != 200) throw SyncException('The provider returned an error (${res.statusCode}).');
    List<int> bytes = res.bodyBytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) bytes = gzip.decode(bytes);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!text.contains('#EXTINF') && !text.contains('://')) {
      throw SyncException('That link did not return an M3U playlist.');
    }
    return text;
  }

  void _storeM3u(int pid, List<M3uEntry> entries) {
    final cats = {for (final k in ContentKind.values) k: <String>[]};
    final seenCats = {for (final k in ContentKind.values) k: <String>{}};
    final channels = <Map<String, Object?>>[];
    final movies = <Map<String, Object?>>[];
    final seriesRows = <String, Map<String, Object?>>{};
    final episodes = <Episode>[];
    var autoNum = 0;
    final usedNums = <int>{};
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var order = 0;

    for (final e in entries) {
      if (seenCats[e.kind]!.add(e.group)) cats[e.kind]!.add(e.group);
      switch (e.kind) {
        case ContentKind.live:
          var n = e.number;
          if (n <= 0 || usedNums.contains(n)) {
            do {
              autoNum++;
            } while (usedNums.contains(autoNum));
            n = autoNum;
          }
          usedNums.add(n);
          channels.add({'stream_id': e.url, 'num': n, 'name': e.name, 'logo': e.logo, 'cat_id': e.group, 'epg_id': e.tvgId, 'url': e.url});
        case ContentKind.movie:
          movies.add({'stream_id': e.url, 'name': e.name, 'poster': e.logo, 'cat_id': e.group, 'url': e.url, 'added': now - order++});
        case ContentKind.series:
          final sid = '${e.group}|${e.seriesName}';
          seriesRows.putIfAbsent(sid, () => {'series_id': sid, 'name': e.seriesName, 'poster': e.logo, 'cat_id': e.group, 'added': now - order++});
          episodes.add(Episode(id: e.url, seriesId: sid, season: e.season, episode: e.episode, title: e.name, url: e.url, image: e.logo));
      }
    }
    for (final k in ContentKind.values) {
      db.insertCategories(pid, k, cats[k]!.map((g) => (g, g)).toList());
    }
    db.insertChannels(pid, channels);
    db.insertMovies(pid, movies);
    db.insertSeries(pid, seriesRows.values);
    db.insertEpisodes(pid, episodes);
  }

  void _storeXtream(
    int pid,
    XtreamApi api,
    bool hls,
    List<Map<String, dynamic>> liveCats,
    List<Map<String, dynamic>> live,
    List<Map<String, dynamic>> vodCats,
    List<Map<String, dynamic>> vod,
    List<Map<String, dynamic>> serCats,
    List<Map<String, dynamic>> ser,
  ) {
    List<(String, String)> catsOf(List<Map<String, dynamic>> raw, List<Map<String, dynamic>> items) {
      final out = raw.map((c) => ('${c['category_id']}', '${c['category_name'] ?? 'Other'}')).toList();
      final known = out.map((c) => c.$1).toSet();
      if (items.any((i) => !known.contains('${i['category_id']}'))) out.add(('0', 'Uncategorised'));
      return out;
    }

    String catOf(Map<String, dynamic> i, Set<String> known) {
      final c = '${i['category_id']}';
      return known.contains(c) ? c : '0';
    }

    final lc = catsOf(liveCats, live);
    final vc = catsOf(vodCats, vod);
    final sc = catsOf(serCats, ser);
    db.insertCategories(pid, ContentKind.live, lc);
    db.insertCategories(pid, ContentKind.movie, vc);
    db.insertCategories(pid, ContentKind.series, sc);
    final lk = lc.map((c) => c.$1).toSet();
    final vk = vc.map((c) => c.$1).toSet();
    final sk = sc.map((c) => c.$1).toSet();

    var auto = 0;
    final used = <int>{};
    db.insertChannels(pid, live.map((s) {
      final id = '${s['stream_id']}';
      var n = int.tryParse('${s['num'] ?? ''}') ?? 0;
      if (n <= 0 || used.contains(n)) {
        do {
          auto++;
        } while (used.contains(auto));
        n = auto;
      }
      used.add(n);
      return {
        'stream_id': id,
        'num': n,
        'name': '${s['name'] ?? 'Channel $n'}'.trim(),
        'logo': s['stream_icon']?.toString(),
        'cat_id': catOf(s, lk),
        'epg_id': '${s['epg_channel_id'] ?? ''}' == 'null' ? '' : '${s['epg_channel_id'] ?? ''}',
        'url': api.liveUrl(id, hls: hls),
      };
    }));
    db.insertMovies(pid, vod.map((s) {
      final id = '${s['stream_id']}';
      return {
        'stream_id': id,
        'name': '${s['name'] ?? 'Movie'}'.trim(),
        'poster': s['stream_icon']?.toString(),
        'cat_id': catOf(s, vk),
        'url': api.movieUrl(id, '${s['container_extension'] ?? 'mp4'}'),
        'rating': '${s['rating'] ?? ''}',
        'year': '${s['year'] ?? ''}',
        'added': int.tryParse('${s['added'] ?? 0}') ?? 0,
      };
    }));
    db.insertSeries(pid, ser.map((s) => {
          'series_id': '${s['series_id']}',
          'name': '${s['name'] ?? 'Series'}'.trim(),
          'poster': s['cover']?.toString(),
          'cat_id': catOf(s, sk),
          'plot': '${s['plot'] ?? ''}',
          'rating': '${s['rating'] ?? ''}',
          'year': '${s['releaseDate'] ?? s['release_date'] ?? ''}'.split('-').first,
          'added': int.tryParse('${s['last_modified'] ?? 0}') ?? 0,
        }));
  }

  /// Downloads and stores the XMLTV guide (often gzipped). Keeps 12 hours
  /// back and 3 days ahead.
  Future<int> syncEpg(int pid, String url, {void Function(String step)? onStep}) async {
    if (url.isEmpty) return 0;
    onStep?.call('Downloading TV guide…');
    final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'LenzoriumPlayer/1.0';
    final res = await _client.send(req).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw SyncException('Guide download failed (${res.statusCode}).');
    final now = DateTime.now();
    var total = 0;
    var first = true;
    await for (final batch in XmltvParser.parse(res.stream,
        from: now.subtract(const Duration(hours: 12)), to: now.add(const Duration(days: 3)))) {
      db.transaction(() {
        if (first) db.clearEpg(pid);
        first = false;
        db.insertEpg(pid, batch.map((p) => (p.channel, p.startMs, p.stopMs, p.title, p.description)));
      });
      total += batch.length;
      onStep?.call('Reading TV guide… $total programmes');
    }
    return total;
  }
}
