import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));

void replaceAll(BuildContext context, Widget page) => Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );

/// True when the screen is phone-sized (portrait or small landscape).
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

final _hm = DateFormat('HH:mm');
final _date = DateFormat('d MMM yyyy');
final _day = DateFormat('EEEE d MMMM');

String hm(DateTime t) => _hm.format(t);
String dateLong(DateTime t) => _date.format(t);
String dayLong(DateTime t) => _day.format(t);

String durationText(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String minutesLeft(int posMs, int durMs) {
  final left = ((durMs - posMs) / 60000).round();
  return left <= 0 ? 'Finished' : '$left min left';
}
