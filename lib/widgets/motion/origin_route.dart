// A page that opens out of the thing that was tapped, the way an app opens
// from its icon: the tapped widget grows into the full page, and closing
// shrinks the page back into it. The back gesture pulls the page toward the
// widget before letting go.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/motion/route_back_gesture.dart';
import 'package:waffr/widgets/motion/slide_route.dart';

/// A route to [builder]'s page that opens from [origin]'s place on screen.
/// Falls back to the plain page transition when [origin] has not been laid
/// out or already fills the screen. [radius] is the tapped widget's corner
/// radius.
Route<T> originPageRoute<T>(
  BuildContext origin,
  WidgetBuilder builder, {
  double radius = 22,
}) {
  final box = origin.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) {
    return MaterialPageRoute<T>(builder: builder);
  }
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.sizeOf(origin);
  // Nothing to grow out of when the caller is the page itself.
  if (!screen.isEmpty &&
      rect.width > screen.width * 0.94 &&
      rect.height > screen.height * 0.6) {
    return MaterialPageRoute<T>(builder: builder);
  }
  return OriginPageRoute<T>(builder: builder, origin: rect, radius: radius);
}

/// A [MaterialPageRoute] whose page expands from [origin].
class OriginPageRoute<T> extends MaterialPageRoute<T> {
  /// Where on screen the page opens from, in global coordinates.
  final Rect origin;

  /// Corner radius of the thing the page opens from.
  final double radius;

  /// Creates an [OriginPageRoute].
  OriginPageRoute({
    required super.builder,
    required this.origin,
    this.radius = 22,
  });

  /// The page's growth; the same curve backwards when it closes. It has no
  /// long tail, so the page lands instead of drifting into place.
  static const Curve curve = Curves.fastOutSlowIn;

  /// How far the back gesture shrinks the page toward its origin.
  static const double _pull = 0.16;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  /// The page underneath stays where it is; this page grows over it.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  static double _valueForGesture(double progress) =>
      invertCurve(curve, 1 - progress * _pull);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return RouteBackGesture(
      route: this,
      valueFor: _valueForGesture,
      // A page pushed over this one slides in, so this one moves aside.
      child: SlideOverTransition(
        animation: kAlwaysCompleteAnimation,
        secondaryAnimation: secondaryAnimation,
        child: _OriginTransition(
          animation: animation,
          origin: origin,
          radius: radius,
          child: child,
        ),
      ),
    );
  }
}

class _OriginTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final double radius;
  final Widget child;

  const _OriginTransition({
    required this.animation,
    required this.origin,
    required this.radius,
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
            final t = OriginPageRoute.curve.transform(value.clamp(0.0, 1.0));
            final rect = Rect.lerp(origin, full, t)!;
            final scale = (rect.width / size.width).clamp(0.01, 1.0);
            // The page shows through as soon as the widget starts to grow,
            // and fades back into the widget at the very end of closing.
            final shown = (t / 0.14).clamp(0.0, 1.0);
            return Stack(
              children: [
                // The page below sinks into a light dusk.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.22 * t),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        lerpDouble(radius, 0, t)!,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.28 * shown * (1 - t),
                          ),
                          blurRadius: 36,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        lerpDouble(radius, 0, t)!,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: size.width,
                        maxWidth: size.width,
                        minHeight: size.height,
                        maxHeight: size.height,
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topCenter,
                          child: Opacity(opacity: shown, child: child),
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
