import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lenzorium_player/models/models.dart';
import 'package:lenzorium_player/services/catalog_db.dart';
import 'package:lenzorium_player/services/m3u_parser.dart';
import 'package:lenzorium_player/services/xmltv_parser.dart';
import 'package:lenzorium_player/services/xtream_api.dart';

void main() {
  group('M3U', () {
    const sample = '''
#EXTM3U url-tvg="http://guide.example/epg.xml.gz"
#EXTINF:-1 tvg-id="news1.uk" tvg-name="Northline News" tvg-logo="http://img/nn.png" group-title="News",Northline News
http://provider.example:8080/live/user/pass/1001.ts
#EXTINF:-1 tvg-id="civic" tvg-chno="7" group-title="News, Politics",Civic Channel, HD
http://provider.example:8080/live/user/pass/1002.m3u8
#EXTINF:-1 tvg-logo="http://img/qh.jpg" group-title="Drama",Quiet Harbour (2024)
http://provider.example:8080/movie/user/pass/2001.mkv
#EXTINF:-1 group-title="Series: Drama",The Long Coast S01 E04
http://provider.example:8080/series/user/pass/3004.mp4
#EXTINF:-1,No Group Channel
#EXTGRP:Misc
http://provider.example/stream
''';

    test('reads attributes, names, groups and the guide link', () {
      final r = M3uParser.parse(sample);
      expect(r.epgUrl, 'http://guide.example/epg.xml.gz');
      expect(r.entries.length, 5);
      final a = r.entries[0];
      expect(a.name, 'Northline News');
      expect(a.tvgId, 'news1.uk');
      expect(a.logo, 'http://img/nn.png');
      expect(a.group, 'News');
      expect(a.kind, ContentKind.live);
    });

    test('commas inside quoted attributes do not split the title', () {
      final b = M3uParser.parse(sample).entries[1];
      expect(b.group, 'News, Politics');
      expect(b.name, 'Civic Channel, HD');
      expect(b.number, 7);
    });

    test('classifies movies and series episodes', () {
      final e = M3uParser.parse(sample).entries;
      expect(e[2].kind, ContentKind.movie);
      expect(e[3].kind, ContentKind.series);
      expect(e[3].seriesName, 'The Long Coast');
      expect(e[3].season, 1);
      expect(e[3].episode, 4);
    });

    test('EXTGRP fallback', () {
      final e = M3uParser.parse(sample).entries[4];
      expect(e.group, 'Misc');
      expect(e.name, 'No Group Channel');
    });

    test('handles CRLF line endings', () {
      final r = M3uParser.parse(sample.replaceAll('\n', '\r\n'));
      expect(r.entries.length, 5);
      expect(r.entries[0].url, 'http://provider.example:8080/live/user/pass/1001.ts');
    });
  });

  group('XMLTV', () {
    test('parses time with offset to UTC', () {
      final ms = XmltvParser.parseTime('20261118210000 +0100')!;
      expect(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true), DateTime.utc(2026, 11, 18, 20));
    });

    test('streams programmes, unescapes text and filters by window', () async {
      const xml = '''<?xml version="1.0"?><tv>
<channel id="news1.uk"><display-name>Northline</display-name></channel>
<programme start="20261118210000 +0000" stop="20261118220000 +0000" channel="news1.uk">
  <title lang="en">Evening &amp; Late</title><desc>Today&#39;s news</desc></programme>
<programme start="20261125210000 +0000" stop="20261125220000 +0000" channel="news1.uk"><title>Far future</title></programme>
</tv>''';
      // Split the input so a programme spans two chunks.
      final bytes = utf8.encode(xml);
      final chunks = Stream<List<int>>.fromIterable([bytes.sublist(0, 150), bytes.sublist(150)]);
      final out = <XmltvProgramme>[];
      await for (final b in XmltvParser.parse(chunks, from: DateTime.utc(2026, 11, 18), to: DateTime.utc(2026, 11, 20))) {
        out.addAll(b);
      }
      expect(out.length, 1);
      expect(out.first.title, 'Evening & Late');
      expect(out.first.description, "Today's news");
      expect(out.first.channel, 'news1.uk');
    });

    test('gunzips gzipped guides', () async {
      const xml = '<tv><programme start="20261118210000 +0000" stop="20261118220000 +0000" channel="a"><title>T</title></programme></tv>';
      final gz = gzip.encode(utf8.encode(xml));
      final out = <XmltvProgramme>[];
      await for (final b in XmltvParser.parse(Stream.value(gz), from: DateTime.utc(2026), to: DateTime.utc(2027))) {
        out.addAll(b);
      }
      expect(out.single.title, 'T');
    });
  });

  group('Xtream', () {
    test('normalises server addresses', () {
      expect(XtreamApi.normaliseServer('provider.example:8080/'), 'http://provider.example:8080');
      expect(XtreamApi.normaliseServer('https://p.example/player_api.php?username=a'), 'https://p.example');
    });

    test('builds stream links', () {
      final x = XtreamApi('http://p.example:8080', 'user', 'pass');
      expect(x.liveUrl('1001'), 'http://p.example:8080/live/user/pass/1001.ts');
      expect(x.liveUrl('1001', hls: true), 'http://p.example:8080/live/user/pass/1001.m3u8');
      expect(x.movieUrl('2001', 'mkv'), 'http://p.example:8080/movie/user/pass/2001.mkv');
      expect(x.seriesUrl('3004', 'mp4'), 'http://p.example:8080/series/user/pass/3004.mp4');
    });
  });

  group('Catalogue database', () {
    test('stores, searches, favourites and history', () {
      final db = CatalogDb.memory();
      final pid = db.addPlaylist(PlaylistSource(name: 'Home', type: SourceType.m3uUrl, url: 'http://x'));
      db.insertCategories(pid, ContentKind.live, [('News', 'News')]);
      db.insertChannels(pid, [
        {'stream_id': 's1', 'num': 101, 'name': 'Northline News', 'logo': null, 'cat_id': 'News', 'epg_id': 'n', 'url': 'http://a'},
        {'stream_id': 's2', 'num': 102, 'name': 'Civic Channel', 'logo': null, 'cat_id': 'News', 'epg_id': '', 'url': 'http://b'},
      ]);
      expect(db.categories(pid, ContentKind.live).single.count, 2);
      expect(db.search(pid, 'north').channels.single.number, 101);
      expect(db.channelByNumber(pid, 102)!.name, 'Civic Channel');
      expect(db.toggleFavourite(pid, ContentKind.live, 's2'), true);
      expect(db.channels(pid, Category.favId).single.streamId, 's2');
      db.saveHistory(pid, HistoryItem(kind: 'movie', key: 'm1', title: 'Film', positionMs: 1000, durationMs: 10000, updated: DateTime.now()));
      expect(db.recent(pid).single.progress, closeTo(0.1, 0.001));
      db.close();
    });
  });
}
