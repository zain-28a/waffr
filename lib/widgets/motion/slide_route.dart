// The app's page transition: the new page slides in from the right edge
// over the old one, which eases a little to the left and dims. Leaving
// plays the same move backwards. The back gesture is a sideways slide too:
// the page travels with the finger, toward the right for a swipe from the
// left edge and toward the left for one from the right edge, and leaves
// that way when the finger lets go.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SwipeEdge;
import 'package:waffr/widgets/motion/route_back_gesture.dart';

/// Slide-over transition for every [MaterialPageRoute].
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates a [SlidePageTransitionsBuilder].
  const SlidePageTransitionsBuilder();

  /// The page's travel; the same curve backwards when it leaves.
  static const Curve curve = Curves.easeOutCubic;

  /// How far the back gesture carries the page at full progress, as a
  /// share of its width: close to the finger's own travel.
  static const double _pull = 0.72;

  /// Which way pages travel: 1 toward the right edge, the usual way; -1
  /// while a back gesture from the right edge carries the page left. Only
  /// one gesture runs at a time, so one value serves every page.
  static final ValueNotifier<double> side = ValueNotifier<double>(1);

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 340);

  /// The animation value that leaves the page pulled aside by the gesture.
  static double valueForGesture(double progress) =>
      invertCurve(curve, 1 - progress * _pull);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return RouteBackGesture(
      route: route,
      valueFor: valueForGesture,
      onStart: (edge) => side.value = edge == SwipeEdge.right ? -1 : 1,
      onEnd: () => side.value = 1,
      child: SlideOverTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    );
  }
}

/// Moves [child] in from the right with [animation], and aside to the left
/// under a dim with [secondaryAnimation] when another page covers it. Both
/// mirror while [SlidePageTransitionsBuilder.side] is -1.
class SlideOverTransition extends StatelessWidget {
  /// This page arriving (0..1).
  final Animation<double> animation;

  /// A page arriving on top of this one (0..1); null skips that part.
  final Animation<double>? secondaryAnimation;

  /// The page.
  final Widget child;

  /// Creates a [SlideOverTransition].
  const SlideOverTransition({
    super.key,
    required this.animation,
    this.secondaryAnimation,
    required this.child,
  });

  /// How far the covered page moves aside, as a share of its width.
  static const double _aside = 0.24;

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryAnimation ?? kAlwaysDismissedAnimation;
    return AnimatedBuilder(
      animation: Listenable.merge([
        animation,
        secondary,
        SlidePageTransitionsBuilder.side,
      ]),
      child: child,
      builder: (context, child) {
        const curve = SlidePageTransitionsBuilder.curve;
        final arrived = curve.transform(animation.value.clamp(0.0, 1.0));
        final covered = curve.transform(secondary.value.clamp(0.0, 1.0));
        // At rest the page is just the page: no layers.
        if (arrived >= 1 && covered <= 0) return child!;

        Widget page = child!;
        if (covered > 0) {
          page = Stack(
            fit: StackFit.passthrough,
            children: [
              page,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.2 * covered),
                  ),
                ),
              ),
            ],
          );
        }
        if (arrived < 1) {
          // A soft shade on the page's leading edge lifts it off the one
          // below while it travels.
          page = DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22 * arrived),
                  blurRadius: 28,
                ),
              ],
            ),
            child: page,
          );
        }
        // The covered page waits on the side the top page did not take.
        final side = SlidePageTransitionsBuilder.side.value;
        return FractionalTranslation(
          translation: Offset(side * ((1 - arrived) - _aside * covered), 0),
          child: page,
        );
      },
    );
  }
}
