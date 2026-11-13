// A page that opens out of the thing that was tapped: it grows from that
// widget's place on screen to the full page, and folds back into it when
// closed with the back button. Back gestures (Android predictive back, the
// iOS edge swipe) keep the platform's own transition.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';

/// A route to [builder]'s page that opens from [origin]'s place on screen.
/// Falls back to a plain route when [origin] has not been laid out.
Route<T> originPageRoute<T>(BuildContext origin, WidgetBuilder builder) {
  final box = origin.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return MaterialPageRoute<T>(builder: builder);
  }
  return OriginPageRoute<T>(
    builder: builder,
    origin: box.localToGlobal(Offset.zero) & box.size,
  );
}

/// A [MaterialPageRoute] whose page expands from [origin].
class OriginPageRoute<T> extends MaterialPageRoute<T> {
  /// Where on screen the page opens from, in global coordinates.
  final Rect origin;

  /// Creates an [OriginPageRoute].
  OriginPageRoute({required super.builder, required this.origin});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The platform transition stays mounted the whole time, because it is
    // what listens for back gestures. It only gets the real animation while
    // a gesture drives the route; otherwise it rests fully open and the
    // origin transition does the moving.
    final gesture = navigator?.userGestureInProgress ?? false;
    final plain = gesture || AppMotion.reduced(context);
    return super.buildTransitions(
      context,
      plain ? animation : kAlwaysCompleteAnimation,
      secondaryAnimation,
      plain
          ? child
          : _OriginTransition(
              animation: animation,
              origin: origin,
              child: child,
            ),
    );
  }
}

class _OriginTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final Widget child;

  const _OriginTransition({
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final full = Offset.zero & size;
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final value = animation.value;
            // At rest the page is just the page: no clip, no layers.
            if (value >= 1) return child!;
            final t = AppMotion.standard.transform(value);
            final rect = Rect.lerp(origin, full, t)!;
            final scale = (rect.width / size.width).clamp(0.01, 1.0);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(lerpDouble(26, 0, t)!),
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        // The page fades in as it leaves the tapped thing.
                        child: Opacity(
                          opacity: (value / 0.3).clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
