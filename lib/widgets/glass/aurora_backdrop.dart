// The page light field: a few large, very soft green lights drifting
// slowly behind the content. It gives the glass chrome something to bend
// and keeps the pages from reading as a flat tint.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// Fills its box with the page background and the drifting lights.
///
/// The drift is redrawn about fifteen times a second, not every frame: the
/// lights are large and slow, so this looks the same and leaves an idle
/// screen nearly free. It stops with reduced motion, on hidden tabs and
/// while the app is in the background.
class AuroraBackdrop extends StatefulWidget {
  /// How strong the lights are, 0..1.
  final double intensity;

  /// Creates an [AuroraBackdrop].
  const AuroraBackdrop({super.key, this.intensity = 1});

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with WidgetsBindingObserver {
  static const Duration _step = Duration(milliseconds: 66);

  /// Seconds of drift so far; the painter repaints when it changes.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  void _sync() {
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    final run =
        mounted &&
        AppMotion.enabled(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (run) {
      _timer ??= Timer.periodic(_step, (_) => _time.value += 0.066);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(
          time: _time,
          background: palette.background,
          colors: palette.aurora,
          strength: widget.intensity * (isDark ? 0.34 : 0.5),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Color background;
  final List<Color> colors;
  final double strength;

  _AuroraPainter({
    required this.time,
    required this.background,
    required this.colors,
    required this.strength,
  }) : super(repaint: time);

  /// Rest position, drift radius, size (as shares of the box) and speed.
  static const List<(Offset, double, double, double)> _lights = [
    (Offset(0.12, 0.10), 0.10, 0.95, 0.11),
    (Offset(0.92, 0.38), 0.12, 0.85, 0.08),
    (Offset(0.25, 0.86), 0.10, 1.00, 0.06),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    final t = time.value;
    for (var i = 0; i < _lights.length; i++) {
      final (rest, drift, scale, speed) = _lights[i];
      final phase = t * speed + i * 2.1;
      final center = Offset(
        (rest.dx + drift * math.cos(phase)) * size.width,
        (rest.dy + drift * math.sin(phase * 1.3)) * size.height,
      );
      final radius = size.shortestSide * scale;
      final color = colors[i % colors.length];
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: strength * 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.colors != colors ||
      oldDelegate.strength != strength;
}

/// Puts a page on the light field: the [AuroraBackdrop] behind [child].
/// Used as the body of pushed screens so their glass header has the same
/// living background as the tabs.
class AuroraPage extends StatelessWidget {
  /// The page content.
  final Widget child;

  /// Creates an [AuroraPage].
  const AuroraPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const AuroraBackdrop(), child],
    );
  }
}
