import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/containers/glass.dart';

/// Shared floating chrome for navigation and pinned period controls.
/// Keep the blur clipped to this pill instead of blurring the whole page.
class FloatingGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;

  const FloatingGlass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(32)),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppPalette.of(context).surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(
            foregroundPainter: LiquidGlassPainter(
              radius: radius,
              isDark: isDark,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: liquidGlassFill(
                  surface.withValues(alpha: isDark ? 0.34 : 0.3),
                  isDark: isDark,
                  sheen: isDark ? null : 0.2,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The softly tinted selection bubble shared with the floating navigation.
class FloatingGlassHighlight extends StatelessWidget {
  final double radius;

  const FloatingGlassHighlight({super.key, required this.radius});

  @override
  Widget build(BuildContext context) {
    final accent = AppPalette.of(context).accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.14),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
    );
  }
}
