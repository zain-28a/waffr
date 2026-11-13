// Progress as a filling vessel: a rounded container whose liquid rises to
// the given share, with a slow wave on its surface.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/motion/motion.dart';

/// A small vessel filled to [ratio] (0..1). [child] sits on top, centered
/// (usually the percentage). The surface waves while the page is visible
/// and motion is allowed; otherwise it is flat.
class LiquidVessel extends StatefulWidget {
  /// How full the vessel is, 0..1.
  final double ratio;

  /// Width and height.
  final double size;

  /// Liquid color.
  final Color color;

  /// The empty part of the vessel.
  final Color track;

  /// Corner radius.
  final double radius;

  /// Drawn over the liquid, centered.
  final Widget? child;

  /// Creates a [LiquidVessel].
  const LiquidVessel({
    super.key,
    required this.ratio,
    required this.color,
    required this.track,
    this.size = 64,
    this.radius = 20,
    this.child,
  });

  @override
  State<LiquidVessel> createState() => _LiquidVesselState();
}

class _LiquidVesselState extends State<LiquidVessel>
    with SingleTickerProviderStateMixin {
  /// One pass of the wave across the vessel.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.enabled(context)) {
      if (!_wave.isAnimating) _wave.repeat();
    } else {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedRatio(
          value: widget.ratio.clamp(0.0, 1.0),
          builder: (context, level) => CustomPaint(
            painter: _VesselPainter(
              level: level,
              wave: _wave,
              color: widget.color,
              track: widget.track,
              radius: widget.radius,
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _VesselPainter extends CustomPainter {
  final double level;
  final Animation<double> wave;
  final Color color;
  final Color track;
  final double radius;

  _VesselPainter({
    required this.level,
    required this.wave,
    required this.color,
    required this.track,
    required this.radius,
  }) : super(repaint: wave);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawRect(rect, Paint()..color = track);

    if (level > 0) {
      final surface = size.height * (1 - level);
      // No wave on an empty or a full vessel.
      final swell = level >= 1 ? 0.0 : math.min(2.6, size.height * level * 0.5);
      final phase = wave.value * 2 * math.pi;

      Path liquid(double shift, double scale) {
        final path = Path()..moveTo(0, size.height);
        for (var x = 0.0; x <= size.width; x += 2) {
          final y =
              surface +
              swell *
                  scale *
                  math.sin(x / size.width * 2 * math.pi + phase + shift);
          path.lineTo(x, y);
        }
        return path
          ..lineTo(size.width, size.height)
          ..close();
      }

      canvas
        ..drawPath(
          liquid(math.pi * 0.9, 1.25),
          Paint()..color = color.withValues(alpha: 0.4),
        )
        ..drawPath(liquid(0, 1), Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VesselPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.radius != radius;
}
