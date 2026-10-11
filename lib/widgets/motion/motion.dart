// Shared motion pieces: staggered entrance, rolling money digits and
// animated progress. Timings come from AppMotion. All of them are
// implicit (no work after they settle) and turn themselves off when the
// device asks for reduced motion.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/utils/money.dart';

/// Fades and lifts [child] in once, the first time it is built.
/// [index] staggers siblings so a screen settles top to bottom.
///
/// The widget tree keeps the same shape before, during and after the
/// entrance, so the child is never rebuilt from scratch when it ends (that
/// used to replay the child's own animations a second time).
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;

  /// False shows [child] at rest without an entrance (e.g. a list row that
  /// scrolled back into view).
  final bool play;

  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 18,
    this.play = true,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.play || AppMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    // Short stagger, capped, so a full screen settles within ~650 ms.
    final delay = Duration(milliseconds: 35 * math.min(widget.index, 6));
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FadeTransition only changes the layer alpha, and the child is painted
    // once into its own layer, so moving it does not repaint it each frame.
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final t = _curve.value;
          return Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          );
        },
      ),
    );
  }
}

/// A money amount whose digits roll to the new value, like the streak
/// counter. Grouping commas move with the digits.
class RollingMoney extends StatefulWidget {
  final num value;
  final TextStyle style;

  const RollingMoney({super.key, required this.value, required this.style});

  @override
  State<RollingMoney> createState() => _RollingMoneyState();
}

class _RollingMoneyState extends State<RollingMoney>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.countUp,
    value: 1,
  );
  late String _from = formatMoney(widget.value);
  late String _to = _from;

  @override
  void didUpdateWidget(covariant RollingMoney oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = formatMoney(widget.value);
    if (next == _to) return;
    // Start from what is on screen now, even mid-roll.
    _from = _controller.value < 0.5 ? _from : _to;
    _to = next;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _to,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = AppMotion.enter.transform(_controller.value);
          if (t >= 1 || _from == _to) {
            return Text(_to, style: widget.style, maxLines: 1);
          }
          return RollingText(
            from: _from,
            to: _to,
            progress: t,
            style: widget.style,
          );
        },
      ),
    );
  }
}

/// Odometer text: each character that changes rolls up from the old value
/// to the new one with a slight tilt. [progress] runs 0..1. Strings are
/// right-aligned so units line up with units.
class RollingText extends StatelessWidget {
  final String from;
  final String to;
  final double progress;
  final TextStyle style;

  const RollingText({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final width = math.max(from.length, to.length);
    final oldChars = from.padLeft(width);
    final newChars = to.padLeft(width);
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    final digitWidth = painter.width;
    painter.dispose();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < width; i++)
            _RollingChar(
              from: oldChars[i],
              to: newChars[i],
              progress: progress,
              style: style,
              height: height,
              width: _isDigit(newChars[i]) || _isDigit(oldChars[i])
                  ? digitWidth
                  : null,
            ),
        ],
      ),
    );
  }

  static bool _isDigit(String c) {
    final unit = c.codeUnitAt(0);
    return unit >= 0x30 && unit <= 0x39;
  }
}

class _RollingChar extends StatelessWidget {
  final String from;
  final String to;
  final double progress;
  final TextStyle style;
  final double height;

  /// Fixed slot width for digits; separators size to their glyph.
  final double? width;

  const _RollingChar({
    required this.from,
    required this.to,
    required this.progress,
    required this.style,
    required this.height,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final appearing = from.trim().isEmpty;
    final leaving = to.trim().isEmpty;

    if (from == to) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(child: Text(to, style: style)),
      );
    }

    Widget face(String char, double offset) {
      final tilt = offset.clamp(-1.0, 1.0) * 0.9;
      return Transform.translate(
        offset: Offset(0, offset * height),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateX(tilt),
          child: Opacity(
            opacity: (1 - offset.abs()).clamp(0.0, 1.0),
            child: Center(child: Text(char, style: style)),
          ),
        ),
      );
    }

    final slot = width ?? _glyphWidth(leaving ? from : to);
    final slotWidth = appearing
        ? slot * progress
        : leaving
        ? slot * (1 - progress)
        : slot;

    return ClipRect(
      child: SizedBox(
        width: slotWidth,
        height: height,
        child: OverflowBox(
          maxWidth: slot,
          minWidth: slot,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!appearing) face(from, -progress),
              if (!leaving) face(to, 1 - progress),
            ],
          ),
        ),
      ),
    );
  }

  double _glyphWidth(String char) {
    final painter = TextPainter(
      text: TextSpan(text: char, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }
}

/// Animates a 0..1 ratio to its new value, starting from 0 on first build so
/// bars fill in when a screen opens.
class AnimatedRatio extends StatelessWidget {
  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  const AnimatedRatio({
    super.key,
    required this.value,
    required this.builder,
    this.duration = AppMotion.countUp,
  });

  @override
  Widget build(BuildContext context) {
    final target = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    if (AppMotion.reduced(context)) return builder(context, target);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: duration,
      curve: AppMotion.enter,
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// Wraps each child of a column in [Reveal] with a rising index, so the
/// column settles top to bottom. Spacers are left as they are, and so is
/// everything past the first screenful, which would only appear on scroll.
/// A child's key is carried onto its wrapper so keyed children still move
/// with their state.
List<Widget> staggered(List<Widget> children, {double offset = 18}) {
  const limit = 10;
  var index = 0;
  return [
    for (final child in children)
      (child is SizedBox && child.child == null) || index >= limit
          ? child
          : Reveal(
              key: child.key == null ? null : ValueKey<Key>(child.key!),
              index: index++,
              offset: offset,
              child: child,
            ),
  ];
}

/// Uncovers [child] left to right as [fraction] goes 0..1. Used to draw a
/// chart in as if a pen were tracing it.
class RevealClip extends StatelessWidget {
  final double fraction;
  final Widget child;

  const RevealClip({super.key, required this.fraction, required this.child});

  @override
  Widget build(BuildContext context) {
    // Always the same ClipRect, so the child is not rebuilt when the reveal
    // completes; a finished reveal simply stops clipping.
    return ClipRect(
      clipper: _FractionClipper(fraction.clamp(0.0, 1.0)),
      clipBehavior: fraction >= 1 ? Clip.none : Clip.hardEdge,
      child: child,
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  final double fraction;

  const _FractionClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, -size.height, size.width * fraction, size.height * 3);

  @override
  bool shouldReclip(covariant _FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
