// Lets a route follow Android's predictive back gesture with its own
// transition: while the finger drags from the edge the route's animation is
// scrubbed, then the route either leaves (released) or returns (cancelled).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

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

  /// The route's content.
  final Widget child;

  /// Creates a [RouteBackGesture].
  const RouteBackGesture({
    super.key,
    this.route,
    required this.valueFor,
    required this.child,
  });

  @override
  State<RouteBackGesture> createState() => _RouteBackGestureState();
}

class _RouteBackGestureState extends State<RouteBackGesture>
    with WidgetsBindingObserver {
  ModalRoute<Object?>? _route;
  bool _dragging = false;

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
    super.dispose();
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
  }

  @override
  void handleCommitBackGesture() {
    if (!_dragging) return;
    _dragging = false;
    _route?.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
