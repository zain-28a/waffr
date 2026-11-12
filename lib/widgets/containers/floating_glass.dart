// Floating liquid-glass chrome: the refracting pill behind the bottom bar
// and the pinned period selector, and its selection bubble.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/glass/liquid_glass.dart';

/// Shared floating chrome for navigation and pinned period controls.
/// A [LiquidGlass] pill: it bends and lightly blurs what scrolls beneath.
class FloatingGlass extends StatelessWidget {
  /// Content inside the glass.
  final Widget child;

  /// Corner radius of the pill.
  final BorderRadius radius;

  /// Creates a [FloatingGlass].
  const FloatingGlass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(32)),
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(radius: radius, child: child);
  }
}

/// The softly tinted selection bubble shared with the floating navigation.
class FloatingGlassHighlight extends StatelessWidget {
  /// Corner radius of the bubble.
  final double radius;

  /// Creates a [FloatingGlassHighlight].
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
