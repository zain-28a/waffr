// Tilt for dimensional surfaces: how far a card leans toward the viewer's
// finger and with the phone's own motion, as one spring-smoothed offset.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/theme/app_motion.dart';

/// Whether dimensional cards follow the phone's motion. Stored in prefs;
/// on by default. Touch tilt always works.
class TiltSettings extends ChangeNotifier {
  TiltSettings._();

  /// The app-wide setting.
  static final TiltSettings instance = TiltSettings._();

  static const String _key = 'motion_tilt_enabled';

  bool _enabled = true;
  bool _loaded = false;

  /// True when cards may follow the phone's motion.
  bool get enabled => _enabled;

  /// Reads the stored choice once.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await AppPrefs.instance;
    final stored = prefs.getBool(_key) ?? true;
    if (stored != _enabled) {
      _enabled = stored;
      notifyListeners();
    }
  }

  /// Turns motion tilt on or off and remembers it.
  Future<void> setEnabled(bool value) async {
    _loaded = true;
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await AppPrefs.instance;
    await prefs.setBool(_key, value);
  }
}

/// Builds [builder] with the current tilt: x and y in -1..1, positive x
/// toward the right edge and positive y toward the bottom.
///
/// The tilt follows a finger while it is on the surface and the phone's
/// accelerometer while [motion] is true. Both ease through springs and
/// return to rest; reduced motion keeps the surface flat.
class TiltBuilder extends StatefulWidget {
  /// Follow the phone's motion too (needs [TiltSettings.enabled]).
  final bool motion;

  /// Builds the tilted surface.
  final Widget Function(BuildContext context, Offset tilt, Widget? child)
  builder;

  /// Passed through to [builder].
  final Widget? child;

  /// Creates a [TiltBuilder].
  const TiltBuilder({
    super.key,
    required this.builder,
    this.motion = true,
    this.child,
  });

  @override
  State<TiltBuilder> createState() => _TiltBuilderState();
}

class _TiltBuilderState extends State<TiltBuilder>
    with TickerProviderStateMixin {
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _y = AnimationController.unbounded(
    vsync: this,
  );

  /// Lean from the phone's motion; changes a little on every sensor event.
  final ValueNotifier<Offset> _sensor = ValueNotifier<Offset>(Offset.zero);

  StreamSubscription<AccelerometerEvent>? _events;

  /// The pose the phone is usually held in; lean is measured from it, so
  /// any resting angle reads as flat and only movement tilts the card.
  Offset? _baseline;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    TiltSettings.instance.addListener(_sync);
    TiltSettings.instance.ensureLoaded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TiltBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Listens to the accelerometer only on a visible, motion-enabled page.
  void _sync() {
    if (!mounted) return;
    final listen =
        widget.motion &&
        TiltSettings.instance.enabled &&
        AppMotion.enabled(context);
    if (listen && _events == null) {
      // The plugin reports a missing sensor (desktop, tests) as an error
      // outside the stream; the guarded zone keeps that quiet and the card
      // simply stays with touch tilt.
      runZonedGuarded(() {
        _events =
            accelerometerEventStream(
              samplingPeriod: SensorInterval.gameInterval,
            ).listen(
              _onMotion,
              onError: (Object _) => _stopMotion(),
              cancelOnError: true,
            );
      }, (Object _, StackTrace _) => _stopMotion());
    } else if (!listen && _events != null) {
      _stopMotion();
    }
  }

  void _stopMotion() {
    _events?.cancel().catchError((Object _) {});
    _events = null;
    _baseline = null;
    if (mounted) _sensor.value = Offset.zero;
  }

  void _onMotion(AccelerometerEvent event) {
    // Gravity along the screen's x and y, about -1..1.
    final pose = Offset(-event.x / 9.81, event.y / 9.81);
    final baseline = _baseline ?? pose;
    // The baseline creeps after the pose, so a held angle settles flat.
    _baseline = baseline + (pose - baseline) * 0.02;
    final lean = (pose - baseline) * 3.2;
    final target = Offset(lean.dx.clamp(-1.0, 1.0), lean.dy.clamp(-1.0, 1.0));
    final next = _sensor.value + (target - _sensor.value) * 0.18;
    // Ignore sensor noise so a still phone does not repaint the card.
    if ((next - _sensor.value).distanceSquared > 0.000004) {
      _sensor.value = next;
    }
  }

  void _lean(Offset local, Size size) {
    if (size.isEmpty) return;
    final reduced = AppMotion.reduced(context);
    if (reduced) return;
    _x.springTo(
      (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      spring: AppSprings.spatial,
    );
    _y.springTo(
      (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      spring: AppSprings.spatial,
    );
  }

  void _release() {
    _touching = false;
    final reduced = AppMotion.reduced(context);
    _x.springTo(0, spring: AppSprings.spatialSlow, reduced: reduced);
    _y.springTo(0, spring: AppSprings.spatialSlow, reduced: reduced);
  }

  @override
  void dispose() {
    TiltSettings.instance.removeListener(_sync);
    _events?.cancel().catchError((Object _) {});
    _sensor.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _touching = true;
        _lean(event.localPosition, context.size ?? Size.zero);
      },
      onPointerMove: (event) {
        if (_touching) _lean(event.localPosition, context.size ?? Size.zero);
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_x, _y, _sensor]),
        child: widget.child,
        builder: (context, child) {
          final tilt = Offset(
            (_x.value + _sensor.value.dx).clamp(-1.0, 1.0),
            (_y.value + _sensor.value.dy).clamp(-1.0, 1.0),
          );
          return widget.builder(context, tilt, child);
        },
      ),
    );
  }
}
