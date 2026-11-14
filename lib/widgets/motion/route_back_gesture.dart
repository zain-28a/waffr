// Lets a route follow Android's predictive back gesture with its own
// transition: while the finger drags from the edge the route's animation is
// scrubbed, then the route either leaves from where it was let go
// (released) or returns (cancelled).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent, SwipeEdge;

/// Finds the animation value at which [curve] reaches [output]; for the
/// rising curves used by route transitions.
double invertCurve(Curve curve, double output) {
  final target = output.clamp(0.0, 1.0);
  var low = 0.0;
  var high = 1.0;
  for (var step = 0; step < 22; step++) {
    final middle = (low + high) / 2;
    if (curve.transform(middle) < target) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

/// Scrubs [route]'s animation with the back gesture. [valueFor] maps the
/// gesture's progress (0..1) to the route's animation value (1 is fully
/// open). Back button presses are left to the navigator.
class RouteBackGesture extends StatefulWidget {
  /// The route to drive; defaults to the enclosing one.
  final ModalRoute<Object?>? route;

  /// Route animation value for a gesture progress.
  final double Function(double progress) valueFor;

  /// Called when a gesture takes hold of the route, with the screen edge
  /// the finger came from.
  final ValueChanged<SwipeEdge>? onStart;

  /// Called once the route has come to rest after that gesture: gone, or
  /// back in place.
  final VoidCallback? onEnd;

  /// The route's content.
  final Widget child;

  /// Creates a [RouteBackGesture].
  const RouteBackGesture({
    super.key,
    this.route,
    required this.valueFor,
    this.onStart,
    this.onEnd,
    required this.child,
  });

  @override
  State<RouteBackGesture> createState() => _RouteBackGestureState();
}

class _RouteBackGestureState extends State<RouteBackGesture>
    with WidgetsBindingObserver {
  ModalRoute<Object?>? _route;
  bool _dragging = false;

  /// The animation being watched until the route rests after a gesture.
  Animation<double>? _settling;

  /// The navigator still to be told the gesture is over, after a commit.
  NavigatorState? _owedStop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = widget.route ?? ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant RouteBackGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    _route = widget.route ?? ModalRoute.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finish();
    super.dispose();
  }

  /// Waits for the route to stop moving, then reports the gesture over.
  void _watchSettle() {
    final animation = _route?.animation;
    if (animation == null || animation.isCompleted || animation.isDismissed) {
      _finish(force: true);
      return;
    }
    if (_settling != null) return;
    _settling = animation..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted || status.isDismissed) _finish();
  }

  void _finish({bool force = false}) {
    final settling = _settling;
    if (settling == null && !force) return;
    settling?.removeStatusListener(_onStatus);
    _settling = null;
    _owedStop?.didStopUserGesture();
    _owedStop = null;
    widget.onEnd?.call();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = _route;
    if (route == null ||
        backEvent.isButtonEvent ||
        !route.isCurrent ||
        route.isFirst ||
        route.popDisposition != RoutePopDisposition.pop ||
        route.animation?.isCompleted != true) {
      return false;
    }
    _dragging = true;
    widget.onStart?.call(backEvent.swipeEdge);
    route.handleStartBackGesture(progress: _value(backEvent.progress));
    return true;
  }

  double _value(double progress) =>
      widget.valueFor(progress.clamp(0.0, 1.0)).clamp(0.0, 1.0);

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_dragging) return;
    _route?.handleUpdateBackGestureProgress(
      progress: _value(backEvent.progress),
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!_dragging) return;
    _dragging = false;
    _route?.handleCancelBackGesture();
    _watchSettle();
  }

  @override
  void handleCommitBackGesture() {
    if (!_dragging) return;
    _dragging = false;
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null || !route.isCurrent) {
      route?.handleCancelBackGesture();
      _watchSettle();
      return;
    }
    // Pop from where the finger left the route. The route's own commit
    // would first snap it fully open and play the whole exit again, which
    // reads as a jump back under the finger.
    _owedStop = navigator;
    navigator.pop();
    _watchSettle();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
