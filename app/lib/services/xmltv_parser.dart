import 'dart:async';
import 'dart:convert';
import 'dart:io';

class XmltvProgramme {
  XmltvProgramme(this.channel, this.startMs, this.stopMs, this.title, this.description);
  final String channel;
  final int startMs;
  final int stopMs;
  final String title;
  final String description;
}

/// Streaming XMLTV reader. Guide files are often tens of MB (gzipped), so
/// it scans `<programme>` blocks chunk by chunk instead of building a DOM,
/// and keeps only programmes inside [from]..[to].
class XmltvParser {
  static final _startRe = RegExp(r'\bstart="([^"]+)"');
  static final _stopRe = RegExp(r'\bstop="([^"]+)"');
  static final _chanRe = RegExp(r'\bchannel="([^"]+)"');
  static final _titleRe = RegExp(r'<title[^>]*>([\s\S]*?)</title>');
  static final _descRe = RegExp(r'<desc[^>]*>([\s\S]*?)</desc>');

  /// Gunzips if the stream starts with the gzip magic bytes.
  static Stream<List<int>> maybeGunzip(Stream<List<int>> source) async* {
    final it = StreamIterator(source);
    if (!await it.moveNext()) return;
    final first = it.current;
    Stream<List<int>> rest() async* {
      yield first;
      while (await it.moveNext()) {
        yield it.current;
      }
    }

    if (first.length >= 2 && first[0] == 0x1f && first[1] == 0x8b) {
      yield* rest().transform(gzip.decoder);
    } else {
      yield* rest();
    }
  }

  /// Emits programmes in batches of up to [batchSize].
  static Stream<List<XmltvProgramme>> parse(
    Stream<List<int>> bytes, {
    required DateTime from,
    required DateTime to,
    int batchSize = 2000,
  }) async* {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    var buf = '';
    var batch = <XmltvProgramme>[];

    await for (final chunk in maybeGunzip(bytes).transform(const Utf8Decoder(allowMalformed: true))) {
      buf += chunk;
      var pos = 0;
      while (true) {
        final s = buf.indexOf('<programme', pos);
        if (s < 0) {
          pos = buf.length;
          break;
        }
        final e = buf.indexOf('</programme>', s);
        if (e < 0) {
          pos = s;
          break;
        }
        final p = parseBlock(buf.substring(s, e));
        pos = e + 12;
        if (p != null && p.stopMs > fromMs && p.startMs < toMs) {
          batch.add(p);
          if (batch.length >= batchSize) {
            yield batch;
            batch = <XmltvProgramme>[];
          }
        }
      }
      buf = pos >= buf.length ? '' : buf.substring(pos);
    }
    if (batch.isNotEmpty) yield batch;
  }

  static XmltvProgramme? parseBlock(String block) {
    final tagEnd = block.indexOf('>');
    if (tagEnd < 0) return null;
    final head = block.substring(0, tagEnd);
    final start = parseTime(_startRe.firstMatch(head)?.group(1));
    final stop = parseTime(_stopRe.firstMatch(head)?.group(1));
    final chan = _chanRe.firstMatch(head)?.group(1);
    if (start == null || chan == null) return null;
    final title = unescape(_titleRe.firstMatch(block)?.group(1) ?? '');
    final desc = unescape(_descRe.firstMatch(block)?.group(1) ?? '');
    return XmltvProgramme(unescape(chan), start, stop ?? start + 3600000, title.trim(), desc.trim());
  }

  /// "20261118210000 +0000" → UTC epoch milliseconds.
  static int? parseTime(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.length < 12) return null;
    final y = int.tryParse(t.substring(0, 4));
    final mo = int.tryParse(t.substring(4, 6));
    final d = int.tryParse(t.substring(6, 8));
    final h = int.tryParse(t.substring(8, 10));
    final mi = int.tryParse(t.substring(10, 12));
    final se = t.length >= 14 ? int.tryParse(t.substring(12, 14)) ?? 0 : 0;
    if (y == null || mo == null || d == null || h == null || mi == null) return null;
    var ms = DateTime.utc(y, mo, d, h, mi, se).millisecondsSinceEpoch;
    final off = RegExp(r'([+-])(\d{2}):?(\d{2})\s*$').firstMatch(t.length > 14 ? t.substring(14) : '');
    if (off != null) {
      final sign = off.group(1) == '-' ? -1 : 1;
      final mins = int.parse(off.group(2)!) * 60 + int.parse(off.group(3)!);
      ms -= sign * mins * 60000;
    }
    return ms;
  }

  static String unescape(String s) {
    if (!s.contains('&') && !s.contains('<![CDATA[')) return s;
    var r = s.replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m.group(1)!);
    r = r.replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return r
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }
}
