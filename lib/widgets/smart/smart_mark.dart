// The smart analysis mark: a faceted four-point spark with a companion
// spark and a dot, in the smart glow colors, so every place that opens or labels the
// analysis shows the same sign.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/widgets/smart/smart_glow.dart';

class SmartMark extends StatelessWidget {
  final double size;

  /// 0..1; animating it makes the small spark and dot breathe.
  final double phase;

  /// Draws every part in one flat color instead of the gradient, e.g. on an
  /// accent fill.
  final Color? color;

  const SmartMark({super.key, this.size = 24, this.phase = 0, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = smartGlowColors(context);
    return Semantics(
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: SmartMarkPainter(
            colors: colors,
            phase: phase,
            flat: color,
          ),
        ),
      ),
    );
  }
}

class SmartMarkPainter extends CustomPainter {
  final List<Color> colors;
  final double phase;
  final Color? flat;

  const SmartMarkPainter({
    required this.colors,
    required this.phase,
    this.flat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final bounds = Offset.zero & size;

    final paint = Paint()..isAntiAlias = true;
    if (flat != null) {
      paint.color = flat!;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors[1], colors[2], colors[3]],
      ).createShader(bounds);
    }

    final main = Offset(size.width * 0.42, size.height * 0.58);
    final pulse = 0.85 + 0.15 * math.cos(phase * 2 * math.pi);

    // Soft halo so the mark has some depth on any background.
    if (flat == null) {
      final halo = s * 0.46;
      canvas.drawCircle(
        main,
        halo,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[2].withValues(alpha: 0.22),
              colors[2].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: main, radius: halo)),
      );
    }

    // Main spark, with a lighter inner facet that catches the light.
    canvas.drawPath(_spark(main, s * 0.42), paint);
    canvas.drawPath(
      _spark(main, s * 0.2),
      Paint()
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: flat == null ? 0.45 : 0.3),
    );

    // Companion spark (breathes while it "thinks") and a small dot.
    canvas.drawPath(
      _spark(Offset(size.width * 0.82, size.height * 0.2), s * 0.17 * pulse),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.8),
      s * 0.05 * (2 - pulse),
      paint,
    );
  }

  // Four-point spark with concave sides.
  static Path _spark(Offset c, double r) {
    final k = r * 0.2;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(SmartMarkPainter old) =>
      old.phase != phase ||
      old.flat != flat ||
      !_sameColors(old.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
