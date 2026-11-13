// The Waffr wallet's mouth as a vector: one pose per SmileForm, a tween that
// morphs between poses, and the painter. Shared by the header logo and the
// profile backdrop, which draw it over mouthless copies of the logo.

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';

/// One pose of the mouth, in shares of the 1440 px logo square. Both lips
/// are cubic curves between the two corners; depths are how far their
/// control points sit below the corners (negative is above) and pulls how
/// far those points sit in from the corners, as a share of the half width.
@immutable
class MouthShape {
  /// Half the corner-to-corner width.
  final double halfWidth;

  /// Height of both corners.
  final double cornerY;

  /// Upper lip control depth.
  final double upperDepth;

  /// Lower lip control depth.
  final double lowerDepth;

  /// Upper lip control pull.
  final double upperPull;

  /// Lower lip control pull.
  final double lowerPull;

  /// A pose.
  const MouthShape({
    required this.halfWidth,
    required this.cornerY,
    required this.upperDepth,
    required this.lowerDepth,
    required this.upperPull,
    required this.lowerPull,
  });

  /// Horizontal middle of the mouth in the artwork.
  static const double centerX = 651.5 / 1440;

  /// Traced from waffr_logo.png: the logo's own smile, the widest pose.
  static const excellent = MouthShape(
    halfWidth: 301.5 / 1440,
    cornerY: 806.5 / 1440,
    upperDepth: 218 / 1440,
    lowerDepth: 343 / 1440,
    upperPull: 0.49,
    lowerPull: 0.2,
  );

  /// A full smile, a little smaller than the logo's.
  static const happy = MouthShape(
    halfWidth: 272 / 1440,
    cornerY: 836 / 1440,
    upperDepth: 168 / 1440,
    lowerDepth: 270 / 1440,
    upperPull: 0.49,
    lowerPull: 0.2,
  );

  /// A softer smile.
  static const pleased = MouthShape(
    halfWidth: 252 / 1440,
    cornerY: 862 / 1440,
    upperDepth: 112 / 1440,
    lowerDepth: 196 / 1440,
    upperPull: 0.46,
    lowerPull: 0.24,
  );

  /// A slight smile.
  static const content = MouthShape(
    halfWidth: 236 / 1440,
    cornerY: 890 / 1440,
    upperDepth: 52 / 1440,
    lowerDepth: 132 / 1440,
    upperPull: 0.41,
    lowerPull: 0.3,
  );

  /// Close to a straight line.
  static const neutral = MouthShape(
    halfWidth: 222 / 1440,
    cornerY: 917 / 1440,
    upperDepth: -8 / 1440,
    lowerDepth: 76 / 1440,
    upperPull: 0.36,
    lowerPull: 0.36,
  );

  /// Corners turned slightly down.
  static const uneasy = MouthShape(
    halfWidth: 214 / 1440,
    cornerY: 950 / 1440,
    upperDepth: -62 / 1440,
    lowerDepth: 18 / 1440,
    upperPull: 0.26,
    lowerPull: 0.44,
  );

  /// A clear frown.
  static const sad = MouthShape(
    halfWidth: 210 / 1440,
    cornerY: 988 / 1440,
    upperDepth: -136 / 1440,
    lowerDepth: -56 / 1440,
    upperPull: 0.2,
    lowerPull: 0.49,
  );

  /// The pose for a face.
  static MouthShape of(SmileForm form) => switch (form) {
    SmileForm.excellent => excellent,
    SmileForm.happy => happy,
    SmileForm.pleased => pleased,
    SmileForm.content => content,
    SmileForm.neutral => neutral,
    SmileForm.uneasy => uneasy,
    SmileForm.sad => sad,
  };

  /// Highest point any pose reaches, as a share of the mark's size.
  static double get topmost {
    var top = double.infinity;
    for (final form in SmileForm.values) {
      final shape = of(form);
      final upperMid = shape.cornerY + shape.upperDepth * 0.75;
      final high = upperMid < shape.cornerY ? upperMid : shape.cornerY;
      if (high < top) top = high;
    }
    return top;
  }

  /// Linear blend toward [other] at [t].
  MouthShape lerpTo(MouthShape other, double t) {
    double mix(double a, double b) => a + (b - a) * t;
    return MouthShape(
      halfWidth: mix(halfWidth, other.halfWidth),
      cornerY: mix(cornerY, other.cornerY),
      upperDepth: mix(upperDepth, other.upperDepth),
      lowerDepth: mix(lowerDepth, other.lowerDepth),
      upperPull: mix(upperPull, other.upperPull),
      lowerPull: mix(lowerPull, other.lowerPull),
    );
  }

  /// Closed path of both lips for a mark [size] pixels wide.
  Path toPath(double size) {
    final left = (centerX - halfWidth) * size;
    final right = (centerX + halfWidth) * size;
    final y = cornerY * size;
    final half = halfWidth * size;
    final upperIn = upperPull * half;
    final lowerIn = lowerPull * half;
    final upperY = y + upperDepth * size;
    final lowerY = y + lowerDepth * size;

    return Path()
      ..moveTo(left, y)
      ..cubicTo(left + upperIn, upperY, right - upperIn, upperY, right, y)
      ..cubicTo(right - lowerIn, lowerY, left + lowerIn, lowerY, left, y)
      ..close();
  }
}

/// Tween that morphs between mouth poses.
class MouthTween extends Tween<MouthShape> {
  /// Creates a [MouthTween].
  MouthTween({super.begin, super.end});

  @override
  MouthShape lerp(double t) => begin!.lerpTo(end!, t);
}

/// Paints a mouth pose in [color], optionally blurred ([blur] is a share of
/// the mark's width) and faded by [opacity].
class MouthPainter extends CustomPainter {
  /// The pose.
  final MouthShape shape;

  /// Fades the mouth; null paints it fully opaque.
  final Animation<double>? opacity;

  /// Ink color.
  final Color color;

  /// Blur as a share of the mark's width; zero for a sharp mouth.
  final double blur;

  /// Creates a [MouthPainter].
  MouthPainter({
    required this.shape,
    required this.color,
    this.opacity,
    this.blur = 0,
  }) : super(repaint: opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = opacity?.value ?? 1;
    if (alpha <= 0 || size.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color.withValues(alpha: color.a * alpha);
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur * size.width);
    }
    canvas.drawPath(shape.toPath(size.width), paint);
  }

  @override
  bool shouldRepaint(covariant MouthPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.opacity != opacity ||
      oldDelegate.color != color ||
      oldDelegate.blur != blur;
}
