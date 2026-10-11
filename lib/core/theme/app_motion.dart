// Shared motion tokens: one tempo and one set of curves for the whole app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Durations go from quick feedback (press, highlight) up to emphasized
// entrances. Curves pair an entering ease-out with an exiting ease-in.
class AppMotion {
  AppMotion._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration emphasized = Duration(milliseconds: 450);

  // Rolling numbers (balances, totals) need longer to read as counting.
  static const Duration countUp = Duration(milliseconds: 650);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;

  // True when the device asks for reduced motion (accessibility setting).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Repeating effects should only run on the visible, motion-enabled page.
  static bool enabled(BuildContext context) =>
      !reduced(context) && TickerMode.valuesOf(context).enabled;

  // [duration], or zero when the device asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

// Haptic cues, named by intent so screens don't pick raw feedback types.
class AppHaptics {
  AppHaptics._();

  // Moving between options: tabs, segments, pickers.
  static void selection() => HapticFeedback.selectionClick();

  // A save or other completed action.
  static void success() => HapticFeedback.lightImpact();

  // A blocked action or a destructive one.
  static void warning() => HapticFeedback.mediumImpact();
}

// Wraps a page transition so reduced motion shows the new page in place.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  final PageTransitionsBuilder base;

  const ReducedMotionPageTransitionsBuilder(this.base);

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      base.delegatedTransition;

  @override
  Duration get transitionDuration => base.transitionDuration;

  @override
  Duration get reverseTransitionDuration => base.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return base.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
