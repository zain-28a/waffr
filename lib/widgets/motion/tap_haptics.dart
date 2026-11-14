// One light haptic for every tap that lands on something tappable, so
// buttons, rows, chips and switches all answer the finger the same way
// without each of them asking for it.

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:waffr/core/theme/app_motion.dart';

/// Wraps the app. A finger that goes down and comes up in place, quickly,
/// on a widget that handles taps plays [AppHaptics.tick]. Drags, long
/// presses and taps on empty space stay silent. Stronger cues a handler
/// plays itself (a save, a delete) follow the tick and replace it.
class TapHaptics extends StatefulWidget {
  /// The app.
  final Widget child;

  /// Creates a [TapHaptics].
  const TapHaptics({super.key, required this.child});

  @override
  State<TapHaptics> createState() => _TapHapticsState();
}

class _TapHapticsState extends State<TapHaptics> {
  /// Longer than this and the touch is a long press, not a tap.
  static const Duration _longest = Duration(milliseconds: 450);

  int? _pointer;
  Offset _down = Offset.zero;
  Duration _downAt = Duration.zero;
  bool _onTappable = false;

  @override
  void initState() {
    super.initState();
    AppHaptics.ensureLoaded();
  }

  void _onDown(PointerDownEvent event) {
    // Only the first finger counts.
    if (_pointer != null) {
      _onTappable = false;
      return;
    }
    _pointer = event.pointer;
    _down = event.position;
    _downAt = event.timeStamp;
    _onTappable = _tappableAt(event.position, event.viewId);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final still = (event.position - _down).distance <= kTouchSlop;
    final quick = event.timeStamp - _downAt <= _longest;
    if (_onTappable && still && quick) AppHaptics.tick();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  /// True when something under [position] answers taps.
  bool _tappableAt(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderSemanticsGestureHandler && target.onTap != null) {
        return true;
      }
      if (target is RenderSemanticsAnnotations &&
          target.properties.onTap != null &&
          target.properties.enabled != false) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
