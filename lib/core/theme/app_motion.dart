// Shared motion tokens: one tempo and one set of curves for the whole app.
// Widgets use these names instead of raw `Curves` and `Duration`s, so the
// feel of the app is tuned in one place.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

/// Duration and curve tokens, plus reduced-motion helpers.
///
/// Durations go from quick feedback (press, highlight) up to emphasized
/// entrances. Curves pair an entering ease-out with an exiting ease-in.
class AppMotion {
  AppMotion._();

  /// Instant feedback: a highlight or a color change.
  static const Duration instant = Duration(milliseconds: 100);

  /// Small changes: presses, chips, switches.
  static const Duration fast = Duration(milliseconds: 200);

  /// The default for most transitions.
  static const Duration medium = Duration(milliseconds: 280);

  /// Larger surfaces: cards expanding, pages of a pager.
  static const Duration slow = Duration(milliseconds: 360);

  /// Entrances that should be noticed: dialogs, first reveals.
  static const Duration emphasized = Duration(milliseconds: 450);

  /// Rolling numbers (balances, totals) need longer to read as counting.
  static const Duration countUp = Duration(milliseconds: 650);

  /// Something arriving: fast start, gentle stop.
  static const Curve enter = Curves.easeOutCubic;

  /// Something leaving: gentle start, fast finish.
  static const Curve exit = Curves.easeInCubic;

  /// Moving from one place to another on screen.
  static const Curve standard = Curves.easeInOutCubic;

  /// A pop that goes a little past its end and settles: badges, dots,
  /// a released button.
  static const Curve overshoot = Curves.easeOutBack;

  /// A lighter ease-out for presses and small progress changes.
  static const Curve soft = Curves.easeOut;

  /// The lighter ease-in that pairs with [soft] when something hides.
  static const Curve softExit = Curves.easeIn;

  /// True when the device asks for reduced motion (accessibility setting).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Repeating effects should only run on the visible, motion-enabled page.
  static bool enabled(BuildContext context) =>
      !reduced(context) && TickerMode.valuesOf(context).enabled;

  /// [duration], or zero when the device asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// The "no animation" duration for [AnimatedSize]. Duration.zero makes it
  /// finish inside its own layout and re-dirty itself, which the framework
  /// rejects, so it gets one microsecond instead.
  static const Duration instantSize = Duration(microseconds: 1);

  /// Like [of] for [AnimatedSize]: [instantSize] under reduced motion.
  static Duration sizeOf(BuildContext context, Duration duration) =>
      reduced(context) ? instantSize : duration;
}

/// Spring tokens. Spatial springs move, resize and reshape things and may
/// overshoot a little; effects springs fade and tint and never overshoot.
/// Values follow the Material 3 Expressive spring set.
class AppSprings {
  AppSprings._();

  /// Small things that follow a finger: presses, toggles, keys.
  static final SpringDescription spatialFast =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 800, ratio: 0.6);

  /// The default for moving surfaces: highlights, cards, sheets.
  static final SpringDescription spatial = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.8,
  );

  /// Large surfaces and full-screen moves.
  static final SpringDescription spatialSlow =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.8);

  /// Opacity, color and light: quick and critically damped.
  static final SpringDescription effects = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1600,
    ratio: 1,
  );
}

/// Drives an unbounded [AnimationController] with a spring.
extension SpringController on AnimationController {
  /// Springs toward [target] from the current value and velocity. With
  /// [reduced] motion the value jumps there instead.
  TickerFuture springTo(
    double target, {
    SpringDescription? spring,
    bool reduced = false,
  }) {
    if (reduced) {
      stop();
      value = target;
      return TickerFuture.complete();
    }
    return animateWith(
      SpringSimulation(spring ?? AppSprings.spatial, value, target, velocity),
    );
  }
}

/// Page steps for period pagers (reports, savings) that honor reduced
/// motion: a jump instead of a slide.
extension AppMotionPaging on PageController {
  /// Moves one page forward, sliding with [AppMotion.medium] unless the
  /// device asks for reduced motion.
  void nextPageFor(BuildContext context) => _step(context, 1);

  /// Moves one page back, like [nextPageFor].
  void previousPageFor(BuildContext context) => _step(context, -1);

  void _step(BuildContext context, int delta) {
    if (!hasClients) return;
    final target = (page ?? initialPage.toDouble()).round() + delta;
    final duration = AppMotion.of(context, AppMotion.medium);
    if (duration == Duration.zero) {
      jumpToPage(target);
    } else {
      animateToPage(target, duration: duration, curve: AppMotion.enter);
    }
  }
}

/// Haptic cues, named by intent so screens don't pick raw feedback types.
///
/// On Android the cues drive the vibrator through the app's own channel:
/// the platform's view haptics stay silent on many phones unless a system
/// setting is on. Elsewhere they use the platform's feedback. The user can
/// turn them off in settings ([enabled]).
class AppHaptics {
  AppHaptics._();

  static const MethodChannel _channel = MethodChannel('waffr/haptics');
  static const String _prefKey = 'haptics_enabled';

  /// Whether cues play at all; mirrors the stored setting.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static bool _loaded = false;

  /// False once the channel turned out to be missing (tests, desktop).
  static bool _native = true;

  /// When the last cue played, so a tap that also triggers a named cue
  /// does not buzz twice.
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Reads the stored setting once.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await AppPrefs.instance;
    enabled.value = prefs.getBool(_prefKey) ?? true;
  }

  /// Turns the cues on or off and remembers it.
  static Future<void> setEnabled(bool value) async {
    _loaded = true;
    enabled.value = value;
    final prefs = await AppPrefs.instance;
    await prefs.setBool(_prefKey, value);
    if (value) selection();
  }

  /// The lightest cue: a plain tap, a key, a step while scrubbing. Skipped
  /// when another cue has only just played.
  static void tick() =>
      _play('tick', HapticFeedback.selectionClick, light: true);

  /// Moving between options: tabs, segments, pickers, switches.
  static void selection() =>
      _play('tick', HapticFeedback.selectionClick, light: true);

  /// A save or other completed action.
  static void success() => _play('click', HapticFeedback.lightImpact);

  /// A blocked action or a destructive one.
  static void warning() => _play('heavy', HapticFeedback.mediumImpact);

  /// A moment worth marking: a goal reached, a streak kept.
  static void celebrate() => _play('double', HapticFeedback.heavyImpact);

  static void _play(
    String kind,
    Future<void> Function() fallback, {
    bool light = false,
  }) {
    if (!enabled.value) return;
    final now = DateTime.now();
    if (light && now.difference(_last).inMilliseconds.abs() < 45) return;
    _last = now;
    final android =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android && _native;
    if (!android) {
      fallback();
      return;
    }
    _channel.invokeMethod<void>('play', kind).catchError((Object _) {
      _native = false;
      fallback();
    });
  }
}

/// Wraps a page transition so reduced motion shows the new page in place.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  /// The transition used when motion is allowed.
  final PageTransitionsBuilder base;

  /// Wraps [base].
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
