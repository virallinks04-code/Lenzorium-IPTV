import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client for the Xtream Codes `player_api.php` interface.
class XtreamApi {
  XtreamApi(String server, this.username, this.password, {http.Client? client})
      : server = normaliseServer(server),
        _client = client ?? http.Client();

  final String server;
  final String username;
  final String password;
  final http.Client _client;

  static String normaliseServer(String s) {
    var v = s.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'http://$v';
    v = v.replaceAll(RegExp(r'/+$'), '');
    v = v.replaceAll(RegExp(r'/player_api\.php.*$'), '');
    return v;
  }

  Uri _api(Map<String, String> params) => Uri.parse('$server/player_api.php').replace(queryParameters: {
        'username': username,
        'password': password,
        ...params,
      });

  Future<dynamic> _get(Map<String, String> params) async {
    final http.Response res;
    try {
      res = await _client.get(_api(params), headers: {'User-Agent': 'LenzoriumPlayer/1.0'}).timeout(const Duration(seconds: 40));
    } catch (e) {
      throw XtreamException('Could not reach the server. Check the address and your connection.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamException('The server refused this username or password.');
    }
    if (res.statusCode != 200) throw XtreamException('Server error (${res.statusCode}).');
    try {
      return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      throw XtreamException('The server did not reply like an Xtream Codes server.');
    }
  }

  Future<AccountInfo> account() async {
    final j = await _get({});
    if (j is! Map || j['user_info'] is! Map) throw XtreamException('Login failed. Check the server, username and password.');
    final u = j['user_info'] as Map;
    if ('${u['auth']}' == '0') throw XtreamException('Login failed. Check the username and password.');
    final exp = int.tryParse('${u['exp_date'] ?? ''}');
    return AccountInfo(
      status: '${u['status'] ?? ''}',
      expires: exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: int.tryParse('${u['max_connections'] ?? 0}') ?? 0,
      activeConnections: int.tryParse('${u['active_cons'] ?? 0}') ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> _list(String action, [Map<String, String> extra = const {}]) async {
    final j = await _get({'action': action, ...extra});
    if (j is List) return j.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    return const [];
  }

  Future<List<Map<String, dynamic>>> liveCategories() => _list('get_live_categories');
  Future<List<Map<String, dynamic>>> liveStreams() => _list('get_live_streams');
  Future<List<Map<String, dynamic>>> vodCategories() => _list('get_vod_categories');
  Future<List<Map<String, dynamic>>> vodStreams() => _list('get_vod_streams');
  Future<List<Map<String, dynamic>>> seriesCategories() => _list('get_series_categories');
  Future<List<Map<String, dynamic>>> seriesList() => _list('get_series');

  Future<MediaDetails> vodInfo(String vodId) async {
    final j = await _get({'action': 'get_vod_info', 'vod_id': vodId});
    final info = (j is Map && j['info'] is Map) ? (j['info'] as Map) : const {};
    final backdrops = info['backdrop_path'];
    return MediaDetails(
      plot: '${info['plot'] ?? info['description'] ?? ''}',
      rating: '${info['rating'] ?? ''}',
      year: '${info['releasedate'] ?? info['release_date'] ?? ''}'.split('-').first,
      genre: '${info['genre'] ?? ''}',
      duration: '${info['duration'] ?? ''}',
      cast: '${info['cast'] ?? info['actors'] ?? ''}',
      backdrop: backdrops is List && backdrops.isNotEmpty ? '${backdrops.first}' : null,
    );
  }

  /// Returns the series' episodes, oldest season first.
  Future<(MediaDetails, List<Episode>)> seriesInfo(String seriesId) async {
    final j = await _get({'action': 'get_series_info', 'series_id': seriesId});
    if (j is! Map) return (MediaDetails(), <Episode>[]);
    final info = j['info'] is Map ? j['info'] as Map : const {};
    final out = <Episode>[];
    void addEp(dynamic e, int fallbackSeason) {
      if (e is! Map) return;
      final id = '${e['id']}';
      final ext = '${e['container_extension'] ?? 'mp4'}';
      final epInfo = e['info'] is Map ? e['info'] as Map : const {};
      out.add(Episode(
        id: id,
        seriesId: seriesId,
        season: int.tryParse('${e['season'] ?? fallbackSeason}') ?? fallbackSeason,
        episode: int.tryParse('${e['episode_num'] ?? 0}') ?? 0,
        title: '${e['title'] ?? 'Episode'}',
        url: seriesUrl(id, ext),
        durationSecs: int.tryParse('${epInfo['duration_secs'] ?? 0}') ?? 0,
        plot: '${epInfo['plot'] ?? ''}',
        image: epInfo['movie_image']?.toString(),
      ));
    }

    final eps = j['episodes'];
    if (eps is Map) {
      eps.forEach((season, list) {
        final s = int.tryParse('$season') ?? 1;
        if (list is List) {
          for (final e in list) {
            addEp(e, s);
          }
        }
      });
    } else if (eps is List) {
      for (final list in eps) {
        if (list is List) {
          for (final e in list) {
            addEp(e, 1);
          }
        }
      }
    }
    out.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));
    final backdrops = info['backdrop_path'];
    return (
      MediaDetails(
        plot: '${info['plot'] ?? ''}',
        rating: '${info['rating'] ?? ''}',
        year: '${info['releaseDate'] ?? info['release_date'] ?? ''}'.split('-').first,
        genre: '${info['genre'] ?? ''}',
        cast: '${info['cast'] ?? ''}',
        backdrop: backdrops is List && backdrops.isNotEmpty ? '${backdrops.first}' : null,
      ),
      out
    );
  }

  /// Now / next for one channel. Titles come base64-encoded.
  Future<List<Programme>> shortEpg(String streamId, {int limit = 4}) async {
    final j = await _get({'action': 'get_short_epg', 'stream_id': streamId, 'limit': '$limit'});
    final list = j is Map ? j['epg_listings'] : null;
    if (list is! List) return const [];
    final out = <Programme>[];
    for (final e in list) {
      if (e is! Map) continue;
      final s = int.tryParse('${e['start_timestamp']}');
      final t = int.tryParse('${e['stop_timestamp']}');
      if (s == null || t == null) continue;
      out.add(Programme(
        start: DateTime.fromMillisecondsSinceEpoch(s * 1000),
        stop: DateTime.fromMillisecondsSinceEpoch(t * 1000),
        title: _b64('${e['title'] ?? ''}'),
        description: _b64('${e['description'] ?? ''}'),
      ));
    }
    return out;
  }

  static String _b64(String s) {
    try {
      return utf8.decode(base64.decode(base64.normalize(s)), allowMalformed: true);
    } catch (_) {
      return s;
    }
  }

  String liveUrl(String streamId, {bool hls = false}) =>
      '$server/live/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$streamId.${hls ? 'm3u8' : 'ts'}';
  String movieUrl(String streamId, String ext) =>
      '$server/movie/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$streamId.$ext';
  String seriesUrl(String episodeId, String ext) =>
      '$server/series/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$episodeId.$ext';
  String xmltvUrl() =>
      '$server/xmltv.php?username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';
}
