import '../models/models.dart';

class M3uEntry {
  M3uEntry({
    required this.name,
    required this.url,
    this.tvgId = '',
    this.logo = '',
    this.group = '',
    this.number = 0,
    this.kind = ContentKind.live,
    this.seriesName = '',
    this.season = 0,
    this.episode = 0,
  });

  final String name;
  final String url;
  final String tvgId;
  final String logo;
  final String group;
  final int number;
  final ContentKind kind;
  final String seriesName;
  final int season;
  final int episode;
}

class M3uResult {
  M3uResult(this.entries, this.epgUrl);
  final List<M3uEntry> entries;
  final String epgUrl;
}

/// Parses M3U / M3U8 (extended) playlists as handed out by IPTV providers.
/// Reads tvg-id, tvg-name, tvg-logo, group-title, tvg-chno and the
/// header's url-tvg / x-tvg-url for the guide.
class M3uParser {
  static final _attr = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
  static final _episode = RegExp(r'^(.*?)[\s._\-|]*S(\d{1,2})\s*[._-]?\s*E(\d{1,3})\b', caseSensitive: false);
  static const _vodExt = ['.mp4', '.mkv', '.avi', '.mov', '.m4v', '.wmv'];

  static M3uResult parse(String text) {
    final entries = <M3uEntry>[];
    var epgUrl = '';
    Map<String, String>? attrs;
    String? title;
    String? extGroup;
    final counters = <String, int>{};

    for (var raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        for (final m in _attr.allMatches(line)) {
          final k = m.group(1)!.toLowerCase();
          if ((k == 'url-tvg' || k == 'x-tvg-url') && epgUrl.isEmpty) {
            epgUrl = m.group(2)!.split(',').first.trim();
          }
        }
        continue;
      }
      if (line.startsWith('#EXTINF')) {
        attrs = {for (final m in _attr.allMatches(line)) m.group(1)!.toLowerCase(): m.group(2)!};
        title = _titleOf(line);
        extGroup = null;
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        extGroup = line.substring(8).trim();
        continue;
      }
      if (line.startsWith('#')) continue;

      // A stream URL line.
      if (attrs == null && title == null) {
        // Plain M3U without #EXTINF: use the URL's last path segment.
        title = Uri.tryParse(line)?.pathSegments.lastOrNull ?? line;
        attrs = {};
      }
      final a = attrs!;
      final name = (title?.isNotEmpty ?? false) ? title! : (a['tvg-name'] ?? 'Channel');
      final group = a['group-title']?.trim().isNotEmpty == true ? a['group-title']!.trim() : (extGroup ?? 'Uncategorised');
      final kind = _kindOf(line);
      var seriesName = '';
      var season = 0;
      var episode = 0;
      var finalKind = kind;
      if (kind != ContentKind.live) {
        final m = _episode.firstMatch(name);
        if (m != null) {
          finalKind = ContentKind.series;
          seriesName = m.group(1)!.trim();
          if (seriesName.isEmpty) seriesName = group;
          season = int.parse(m.group(2)!);
          episode = int.parse(m.group(3)!);
        } else if (kind == ContentKind.series) {
          finalKind = ContentKind.series;
          seriesName = group;
          season = 1;
          episode = counters[group] = (counters[group] ?? 0) + 1;
        }
      }
      entries.add(M3uEntry(
        name: name,
        url: line,
        tvgId: a['tvg-id'] ?? '',
        logo: a['tvg-logo'] ?? a['logo'] ?? '',
        group: group,
        number: int.tryParse(a['tvg-chno'] ?? a['channel-number'] ?? '') ?? 0,
        kind: finalKind,
        seriesName: seriesName,
        season: season,
        episode: episode,
      ));
      attrs = null;
      title = null;
      extGroup = null;
    }
    return M3uResult(entries, epgUrl);
  }

  /// The display name is everything after the first comma that is not
  /// inside a quoted attribute value.
  static String _titleOf(String line) {
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) return line.substring(i + 1).trim();
    }
    return '';
  }

  static ContentKind _kindOf(String url) {
    final u = url.toLowerCase();
    if (u.contains('/series/')) return ContentKind.series;
    if (u.contains('/movie/') || u.contains('/vod/')) return ContentKind.movie;
    if (u.contains('/live/')) return ContentKind.live;
    final path = Uri.tryParse(u)?.path ?? u;
    if (_vodExt.any(path.endsWith)) return ContentKind.movie;
    return ContentKind.live;
  }
}
