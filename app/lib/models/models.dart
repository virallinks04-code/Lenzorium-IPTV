enum SourceType { m3uUrl, m3uFile, xtream }

enum ContentKind { live, movie, series }

String kindKey(ContentKind k) => k.name;
ContentKind kindFrom(String s) => ContentKind.values.firstWhere((k) => k.name == s, orElse: () => ContentKind.live);

class PlaylistSource {
  PlaylistSource({
    this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.username = '',
    this.password = '',
    this.epgUrl = '',
    this.lastSync,
  });

  final int? id;
  final String name;
  final SourceType type;
  /// M3U URL, path of an M3U file copied into app storage, or Xtream server.
  final String url;
  final String username;
  final String password;
  final String epgUrl;
  final DateTime? lastSync;

  PlaylistSource copyWith({int? id, String? name, String? epgUrl, DateTime? lastSync}) => PlaylistSource(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type,
        url: url,
        username: username,
        password: password,
        epgUrl: epgUrl ?? this.epgUrl,
        lastSync: lastSync ?? this.lastSync,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.name,
        'url': url,
        'username': username,
        'password': password,
        'epgUrl': epgUrl,
      };

  static PlaylistSource fromJson(Map<String, dynamic> j) => PlaylistSource(
        name: (j['name'] ?? 'Playlist').toString(),
        type: SourceType.values.firstWhere((t) => t.name == j['type'], orElse: () => SourceType.m3uUrl),
        url: (j['url'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        epgUrl: (j['epgUrl'] ?? '').toString(),
      );
}

class Category {
  Category({required this.id, required this.name, required this.kind, this.count = 0});
  final String id;
  final String name;
  final ContentKind kind;
  final int count;

  static const allId = '__all__';
  static const favId = '__fav__';
  static const recentId = '__recent__';
}

class Channel {
  Channel({
    required this.id,
    required this.streamId,
    required this.name,
    required this.number,
    required this.url,
    this.logo,
    this.categoryId = '',
    this.epgId = '',
  });

  final int id;
  final String streamId;
  final String name;
  final int number;
  final String url;
  final String? logo;
  final String categoryId;
  final String epgId;
}

class Movie {
  Movie({
    required this.id,
    required this.streamId,
    required this.name,
    required this.url,
    this.poster,
    this.categoryId = '',
    this.rating = '',
    this.year = '',
  });

  final int id;
  final String streamId;
  final String name;
  final String url;
  final String? poster;
  final String categoryId;
  final String rating;
  final String year;
}

class Series {
  Series({
    required this.id,
    required this.seriesId,
    required this.name,
    this.poster,
    this.categoryId = '',
    this.plot = '',
    this.rating = '',
    this.year = '',
  });

  final int id;
  final String seriesId;
  final String name;
  final String? poster;
  final String categoryId;
  final String plot;
  final String rating;
  final String year;
}

class Episode {
  Episode({
    required this.id,
    required this.seriesId,
    required this.season,
    required this.episode,
    required this.title,
    required this.url,
    this.durationSecs = 0,
    this.plot = '',
    this.image,
  });

  final String id;
  final String seriesId;
  final int season;
  final int episode;
  final String title;
  final String url;
  final int durationSecs;
  final String plot;
  final String? image;

  String get code => 'S$season · E$episode';
}

class Programme {
  Programme({required this.start, required this.stop, required this.title, this.description = ''});
  final DateTime start;
  final DateTime stop;
  final String title;
  final String description;

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
  double progressAt(DateTime t) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }
}

class MediaDetails {
  MediaDetails({this.plot = '', this.rating = '', this.year = '', this.genre = '', this.duration = '', this.cast = '', this.backdrop});
  final String plot;
  final String rating;
  final String year;
  final String genre;
  final String duration;
  final String cast;
  final String? backdrop;
}

class HistoryItem {
  HistoryItem({
    required this.kind,
    required this.key,
    required this.title,
    this.image,
    this.positionMs = 0,
    this.durationMs = 0,
    this.extra = '',
    required this.updated,
  });

  /// 'live', 'movie' or 'episode'.
  final String kind;
  final String key;
  final String title;
  final String? image;
  final int positionMs;
  final int durationMs;
  /// For episodes: the series id.
  final String extra;
  final DateTime updated;

  double get progress => durationMs <= 0 ? 0 : positionMs / durationMs;
}

class SearchResults {
  SearchResults(this.channels, this.movies, this.series);
  final List<Channel> channels;
  final List<Movie> movies;
  final List<Series> series;
  bool get isEmpty => channels.isEmpty && movies.isEmpty && series.isEmpty;
}

class AccountInfo {
  AccountInfo({this.status = '', this.expires, this.maxConnections = 0, this.activeConnections = 0});
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final int activeConnections;
}
