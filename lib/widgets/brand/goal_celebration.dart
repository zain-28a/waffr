// Full-screen moment shown once when a savings goal is completed: the page
// dims, the wallet hops with its widest smile inside a ring that bursts
// outward with a scatter of stitches, and the goal's name is shown. A tap
// skips it; it removes itself when done.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/brand/waffr_mood_logo.dart';

/// The goal-reached celebration, shown over the app.
class GoalCelebrationOverlay extends StatefulWidget {
  /// Name of the goal that was completed.
  final String goalName;

  /// Called once when the sequence ends or is skipped.
  final VoidCallback onFinished;

  /// Creates a [GoalCelebrationOverlay].
  const GoalCelebrationOverlay({
    super.key,
    required this.goalName,
    required this.onFinished,
  });

  @override
  State<GoalCelebrationOverlay> createState() => _GoalCelebrationOverlayState();
}

class _GoalCelebrationOverlayState extends State<GoalCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 3200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppMotion.reduced(context)) {
        // No sequence: show the result briefly, then leave.
        _controller.value = 0.5;
        Future<void>.delayed(const Duration(milliseconds: 1600), _finish);
        return;
      }
      AppHaptics.success();
      MascotReactions.instance.play(MascotReaction.happy);
      _controller.forward();
    });
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  /// A tap jumps to the fade-out.
  void _skip() {
    if (_controller.value < 0.84) {
      _controller.animateTo(1, duration: AppMotion.medium);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Semantics(
        liveRegion: true,
        label: 'تحقّق هدفك ${widget.goalName}',
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              // In over the first 12%, out over the last 16%.
              final shown =
                  AppMotion.enter.transform((t / 0.12).clamp(0.0, 1.0)) *
                  (1 -
                      AppMotion.exit.transform(
                        ((t - 0.84) / 0.16).clamp(0.0, 1.0),
                      ));
              final burst = AppMotion.enter.transform(
                ((t - 0.1) / 0.45).clamp(0.0, 1.0),
              );
              final rise = AppMotion.overshoot.transform(
                ((t - 0.04) / 0.3).clamp(0.0, 1.0),
              );

              return Opacity(
                opacity: shown.clamp(0.0, 1.0),
                child: ColoredBox(
                  color: palette.background.withValues(alpha: 0.9),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _BurstPainter(
                                    progress: burst,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale: 0.6 + 0.4 * rise,
                                child: const WaffrMoodLogo(
                                  size: 120,
                                  form: SmileForm.excellent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'تحقّق هدفك!',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: const ['Tajawal'],
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            widget.goalName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontFamilyFallback: const ['Tajawal'],
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A ring that grows and thins, with short stitches flying outward.
class _BurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _BurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final reach = size.shortestSide / 2;
    final fade = (1 - progress).clamp(0.0, 1.0);

    canvas.drawCircle(
      center,
      reach * (0.5 + 0.45 * progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + 5 * fade
        ..color = color.withValues(alpha: 0.35 * fade),
    );

    final stitch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.85 * fade);
    const count = 14;
    for (var i = 0; i < count; i++) {
      final angle = i / count * 2 * math.pi + (i.isEven ? 0 : 0.12);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final near = reach * (0.55 + (i.isEven ? 0.38 : 0.3) * progress);
      canvas.drawLine(
        center + direction * near,
        center + direction * (near + 9 * fade + 2),
        stitch,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
