import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// Placeholder Lenzorium lens mark (ring, filled pupil, highlight).
/// Replace with the official SVG/PNG when Lenzorium supplies it.
class LzLogo extends StatelessWidget {
  const LzLogo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 36;
    final c = Offset(18 * s, 18 * s);
    canvas.drawCircle(
        c,
        16 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * s
          ..color = LzColors.text);
    canvas.drawCircle(c, 9 * s, Paint()..color = LzColors.accent);
    canvas.drawCircle(Offset(21.5 * s, 14.5 * s), 2.6 * s, Paint()..color = LzColors.text);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandBar extends StatelessWidget {
  const BrandBar({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const LzLogo(size: 32),
      const SizedBox(width: 12),
      const Text('Lenzorium', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
      const Spacer(),
      if (trailing != null) trailing!,
    ]);
  }
}

class ContentNotice extends StatelessWidget {
  const ContentNotice({super.key});
  @override
  Widget build(BuildContext context) => const Text(
        AppConfig.contentNotice,
        style: TextStyle(fontSize: 14, color: LzColors.faint),
      );
}

/// Network image with a tinted monogram fallback. Used for channel logos
/// and posters, which providers often serve broken or slow.
class LzImage extends StatelessWidget {
  const LzImage({
    super.key,
    required this.url,
    required this.label,
    this.radius = 8,
    this.fit = BoxFit.cover,
    this.monogramSize = 12,
    this.showTitle = false,
  });

  final String? url;
  final String label;
  final double radius;
  final BoxFit fit;
  final double monogramSize;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: LzColors.tintFor(label),
      alignment: showTitle ? Alignment.bottomLeft : Alignment.center,
      padding: EdgeInsets.all(showTitle ? 12 : 2),
      child: Text(
        showTitle ? label : _monogram(label),
        maxLines: showTitle ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: showTitle ? 16 : monogramSize,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.15,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url == null || url!.isEmpty)
          ? fallback
          : Image.network(
              url!,
              fit: fit,
              filterQuality: FilterQuality.medium,
              cacheWidth: 400,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (c, child, p) => p == null ? child : fallback,
            ),
    );
  }

  static String _monogram(String s) {
    final words = s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 3)).toUpperCase();
    return words.take(3).map((w) => w[0]).join().toUpperCase();
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: headline(30)),
          if (subtitle != null) ...[
            const SizedBox(width: 16),
            Flexible(
              child: Text(subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: LzColors.muted)),
            ),
          ],
        ],
      );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key, this.height = 4, this.color = LzColors.muted, this.track = LzColors.surface3});
  final double value;
  final double height;
  final Color color;
  final Color track;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          color: color,
          backgroundColor: track,
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: LzColors.muted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: LzColors.muted, fontSize: 17)),
        ]),
      );
}
