// The Waffr logo as a small character: the mouthless mark with the wallet's
// current smile drawn on top. The smile morphs when the health score moves
// the face to another SmileForm, and the wallet reacts to what the user
// does: a hop when money comes in, a gulp on a big expense.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/brand/waffr_mouth.dart';

/// A moment the wallet reacts to.
enum MascotReaction {
  /// Money came in or a saving was made: a happy hop.
  happy,

  /// A large expense: a gulp.
  gulp,
}

/// Broadcasts reactions to every mascot on screen.
class MascotReactions extends ChangeNotifier {
  MascotReactions._();

  /// The app-wide channel.
  static final MascotReactions instance = MascotReactions._();

  MascotReaction? _latest;

  /// The reaction being announced.
  MascotReaction? get latest => _latest;

  /// Asks the mascots to react.
  void play(MascotReaction reaction) {
    _latest = reaction;
    notifyListeners();
  }
}

/// The logo whose smile follows [WalletMood]. Before the first read it
/// shows the logo's own smile.
class WaffrMoodLogo extends StatefulWidget {
  /// The mark without a mouth (same artwork and size as the logo).
  static const assetPath = 'assets/brand/waffr_logo_mouthless.png';

  /// Width and height.
  final double size;

  /// Overrides [WalletMood] (previews, onboarding and tests).
  final SmileForm? form;

  /// Breathes slowly while idle; for large mascots, not the header.
  final bool idle;

  /// Creates a [WaffrMoodLogo].
  const WaffrMoodLogo({
    super.key,
    this.size = 44,
    this.form,
    this.idle = false,
  });

  @override
  State<WaffrMoodLogo> createState() => _WaffrMoodLogoState();
}

class _WaffrMoodLogoState extends State<WaffrMoodLogo>
    with TickerProviderStateMixin {
  /// The logo's own mouth color.
  static const Color _ink = Color(0xFF135239);

  /// A small round mouth, for the gulp.
  static const MouthShape _gulpMouth = MouthShape(
    halfWidth: 84 / 1440,
    cornerY: 900 / 1440,
    upperDepth: -96 / 1440,
    lowerDepth: 96 / 1440,
    upperPull: 0.18,
    lowerPull: 0.18,
  );

  final WalletMood _mood = WalletMood.instance;
  final MascotReactions _reactions = MascotReactions.instance;

  /// One reaction, start to finish.
  late final AnimationController _react = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// One slow inhale and exhale, when [WaffrMoodLogo.idle].
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  MascotReaction? _reaction;

  /// The mouth worn for the first part of a reaction.
  MouthShape? _reactionMouth;

  @override
  void initState() {
    super.initState();
    _mood.retain();
    _reactions.addListener(_onReaction);
    _react.addListener(_dropReactionMouth);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(covariant WaffrMoodLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBreath();
  }

  void _syncBreath() {
    if (widget.idle && AppMotion.enabled(context)) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  void _onReaction() {
    final reaction = _reactions.latest;
    if (!mounted || reaction == null || !AppMotion.enabled(context)) return;
    setState(() {
      _reaction = reaction;
      _reactionMouth = reaction == MascotReaction.gulp
          ? _gulpMouth
          : MouthShape.excellent;
    });
    _react.forward(from: 0);
  }

  /// The face returns to its mood a little before the body settles.
  void _dropReactionMouth() {
    if (_reactionMouth != null && _react.value > 0.6) {
      setState(() => _reactionMouth = null);
    }
  }

  @override
  void dispose() {
    _reactions.removeListener(_onReaction);
    _mood.release();
    _react.dispose();
    _breath.dispose();
    super.dispose();
  }

  /// Hop or gulp at [t] (0..1), plus the idle breath.
  Matrix4 _pose(double t, double breath) {
    final size = widget.size;
    final wave = math.sin(math.pi * t);
    var dy = 0.0;
    var sx = 1.0;
    var sy = 1.0;
    switch (_reaction) {
      case MascotReaction.happy:
        // Up, down, and a small second bounce.
        final hop = math.sin(math.pi * (t * 2).clamp(0.0, 1.0));
        final echo = t > 0.5 ? math.sin(math.pi * (t - 0.5) * 2) * 0.35 : 0.0;
        dy = -size * 0.13 * (hop + echo);
        sx = 1 + 0.05 * wave;
        sy = 1 + 0.05 * wave;
      case MascotReaction.gulp:
        sx = 1 + 0.07 * wave;
        sy = 1 - 0.09 * wave;
        dy = size * 0.03 * wave;
      case null:
        break;
    }
    final inhale = (1 - math.cos(breath * 2 * math.pi)) / 2;
    sx *= 1 + 0.018 * inhale;
    sy *= 1 + 0.018 * inhale;
    return Matrix4.translationValues(0, dy, 0)..scaleByDouble(sx, sy, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();

    final mark = Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          WaffrMoodLogo.assetPath,
          width: size,
          height: size,
          cacheWidth: pixels,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
        ),
        ListenableBuilder(
          listenable: _mood,
          builder: (context, _) {
            final form = widget.form ?? _mood.form ?? SmileForm.excellent;
            final reacting = _reactionMouth != null;
            return TweenAnimationBuilder<MouthShape>(
              tween: MouthTween(end: _reactionMouth ?? MouthShape.of(form)),
              // Reactions are quick; a change of mood takes its time.
              duration: AppMotion.of(
                context,
                Duration(
                  milliseconds: reacting || _react.isAnimating ? 220 : 900,
                ),
              ),
              curve: AppMotion.standard,
              builder: (context, mouth, _) => CustomPaint(
                painter: MouthPainter(shape: mouth, color: _ink),
              ),
            );
          },
        ),
      ],
    );

    return Semantics(
      image: true,
      label: 'شعار وفّر',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_react, _breath]),
              child: mark,
              builder: (context, child) => Transform(
                alignment: Alignment.bottomCenter,
                transform: _pose(_react.value, _breath.value),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
