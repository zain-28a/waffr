// The "smart analysis" entry point: a compact pill for card headers and a
// full-width banner for the reports tab. Both open SmartAnalysisScreen.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/screens/offline/smart/smart_analysis_screen.dart';
import 'package:waffr/widgets/smart/smart_glow.dart';

class SmartAnalysisButton extends StatefulWidget {
  final InsightScope scope;

  // Full-width card with a subtitle instead of the compact pill.
  final bool banner;

  const SmartAnalysisButton({
    super.key,
    required this.scope,
    this.banner = false,
  });

  @override
  State<SmartAnalysisButton> createState() => _SmartAnalysisButtonState();
}

class _SmartAnalysisButtonState extends State<SmartAnalysisButton>
    with SingleTickerProviderStateMixin {
  // Slow turn of the gradient border so the button reads as "alive".
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _open() {
    AppHaptics.selection();
    openSmartAnalysis(context, widget.scope);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colors = smartGlowColors(context);
    final radius = BorderRadius.circular(widget.banner ? 22 : 999);

    final spark = Hero(
      tag: smartSparkHeroTag(widget.scope),
      child: SmartSpark(size: widget.banner ? 30 : 20),
    );

    final Widget content = widget.banner
        ? Row(
            children: [
              spark,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'التحليل الذكي',
                      style: _text(palette.textPrimary, 15, FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'اكتشف أين يذهب مالك واحصل على اقتراحات',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(palette.textSecondary, 12.5, FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: palette.textSecondary,
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              spark,
              const SizedBox(width: 6),
              Text(
                'تحليل ذكي',
                style: _text(palette.textPrimary, 12.5, FontWeight.w700),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: 'التحليل الذكي',
      child: GestureDetector(
        onTap: _open,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(1.6),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: SweepGradient(
                  colors: [...colors, colors.first],
                  transform: GradientRotation(_turn.value * 2 * math.pi),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors[2].withValues(alpha: 0.18),
                    blurRadius: widget.banner ? 18 : 10,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            padding: widget.banner
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: radius,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  static TextStyle _text(Color color, double size, FontWeight weight) =>
      TextStyle(
        fontFamily: 'Outfit',
        fontFamilyFallback: const ['Tajawal'],
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
}
