// Press feedback shared by every tappable surface: the child compresses a
// little under the finger and springs back on release.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';

/// Wraps [child] with a spring press: it sinks while touched, like a soft
/// physical key, and bounces back when released. Fires a selection haptic
/// on tap unless [haptic] is false.
class Pressable extends StatefulWidget {
  /// The surface to press.
  final Widget child;

  /// Called on tap. Null disables the press feedback too.
  final VoidCallback? onTap;

  /// Called on a long press.
  final VoidCallback? onLongPress;

  /// How far the surface shrinks at full press (0.04 is 4%).
  final double depth;

  /// Fire a light haptic on tap.
  final bool haptic;

  /// Hit-test behavior of the gesture detector.
  final HitTestBehavior behavior;

  /// Creates a [Pressable].
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.depth = 0.04,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  /// 0 at rest, 1 fully pressed; may overshoot slightly below 0 on release.
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  void _to(double target) {
    _press.springTo(
      target,
      spring: AppSprings.spatialFast,
      reduced: AppMotion.reduced(context),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _to(1) : null,
      onTapUp: enabled ? (_) => _to(0) : null,
      onTapCancel: enabled ? () => _to(0) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) AppHaptics.selection();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _to(0);
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (context, child) {
          final p = _press.value.clamp(-0.5, 1.2);
          return Transform.scale(scale: 1 - widget.depth * p, child: child);
        },
      ),
    );
  }
}
