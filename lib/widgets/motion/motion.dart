// Shared motion pieces: staggered entrance, rolling money digits and
// animated progress. Timings come from AppMotion. All of them are
// idle (no work after they settle) and turn themselves off when the
// device asks for reduced motion.
import 'dart:async';
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
  /// The content that enters.
  final Widget child;

  /// Position in the list; later items start a little later.
  final int index;

  /// How far the content rises, in logical pixels.
  final double offset;

  /// False shows [child] at rest without an entrance (e.g. a list row that
  /// scrolled back into view).
  final bool play;

  /// Creates a [Reveal].
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

/// State of [Reveal].
class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );
  bool _started = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) || !widget.play) {
      _started = true;
      _delay?.cancel();
      _controller.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    // Short stagger, capped, so a full screen settles within ~650 ms.
    final delay = Duration(milliseconds: 35 * math.min(widget.index, 6));
    _delay = Timer(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
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
  /// The amount to show.
  final num value;

  /// Text style of the digits.
  final TextStyle style;

  /// Creates a [RollingMoney].
  const RollingMoney({super.key, required this.value, required this.style});

  @override
  State<RollingMoney> createState() => _RollingMoneyState();
}

/// State of [RollingMoney].
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant RollingMoney oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = formatMoney(widget.value);
    if (next == _to) return;
    // Start from what is on screen now, even mid-roll.
    _from = AppMotion.enter.transform(_controller.value) < 0.5 ? _from : _to;
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
///
/// Every character sits where a plain [Text] of the same string would draw
/// it: the old string's layout at 0, the new one's at 1, and in between the
/// two. So the roll ends exactly on the plain text that replaces it, with
/// no jump in width, height or spacing, whatever the font's digit widths.
class RollingText extends StatefulWidget {
  /// Text before the change.
  final String from;

  /// Text after the change.
  final String to;

  /// Roll progress, 0..1.
  final double progress;

  /// Text style.
  final TextStyle style;

  /// Creates a [RollingText].
  const RollingText({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    required this.style,
  });

  @override
  State<RollingText> createState() => _RollingTextState();
}

/// Where each character of a laid-out string starts, plus its end: the
/// pen positions a plain [Text] uses.
class _Carets {
  final List<double> x;
  final double height;

  const _Carets(this.x, this.height);

  double get width => x.last;
}

/// State of [RollingText].
class _RollingTextState extends State<RollingText> {
  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);

  // Layout is independent of animation progress: it is measured again only
  // when a string, the style or the text scale changes.
  TextStyle? _style;
  TextScaler? _scaler;
  TextHeightBehavior? _heightBehavior;
  final Map<String, _Carets> _layouts = {};

  /// The style a [Text] with [RollingText.style] would end up with.
  TextStyle _effectiveStyle() =>
      DefaultTextStyle.of(context).style.merge(widget.style);

  _Carets _carets(String text) => _layouts.putIfAbsent(text, () {
    _painter
      ..text = TextSpan(text: text, style: _style)
      ..textScaler = _scaler!
      ..textHeightBehavior = _heightBehavior
      ..layout();
    // The end is the painted width, as a Text sizes itself: the caret
    // after the last glyph can stop short of it (letter spacing).
    return _Carets([
      for (var k = 0; k < text.length; k++)
        _painter.getOffsetForCaret(TextPosition(offset: k), Rect.zero).dx,
      _painter.width,
    ], _painter.height);
  });

  void _measure() {
    final style = _effectiveStyle();
    final scaler = MediaQuery.textScalerOf(context);
    final heightBehavior = DefaultTextStyle.of(context).textHeightBehavior;
    if (style != _style ||
        scaler != _scaler ||
        heightBehavior != _heightBehavior) {
      _style = style;
      _scaler = scaler;
      _heightBehavior = heightBehavior;
      _layouts.clear();
    }
    // Only the two strings on screen are kept.
    _layouts.removeWhere((text, _) => text != widget.from && text != widget.to);
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final style = _style!;
    final from = _carets(widget.from);
    final to = _carets(widget.to);
    final t = widget.progress.clamp(0.0, 1.0);
    double lerp(double a, double b) => a + (b - a) * t;

    final count = math.max(widget.from.length, widget.to.length);
    final fromPad = count - widget.from.length;
    final toPad = count - widget.to.length;
    final height = math.max(from.height, to.height);

    // Position i of the right-aligned strings: its character, where it
    // starts and how wide it is in each string. A padding position has no
    // character and no width, at the start.
    (String, double, double) slot(String text, _Carets carets, int pad, int i) {
      if (i < pad) return (' ', 0, 0);
      final k = i - pad;
      return (text[k], carets.x[k], carets.x[k + 1] - carets.x[k]);
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: lerp(from.width, to.width),
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < count; i++)
              () {
                final (oldChar, oldX, oldWidth) = slot(
                  widget.from,
                  from,
                  fromPad,
                  i,
                );
                final (newChar, newX, newWidth) = slot(widget.to, to, toPad, i);
                return Positioned(
                  left: lerp(oldX, newX),
                  top: 0,
                  width: lerp(oldWidth, newWidth),
                  height: height,
                  child: _RollingChar(
                    from: oldChar,
                    to: newChar,
                    progress: t,
                    style: style,
                    height: height,
                    faceWidth: math.max(oldWidth, newWidth),
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}

/// One character position of [RollingText]: the old glyph rolls out, the
/// new one rolls in. The slot's width comes from its parent.
class _RollingChar extends StatelessWidget {
  final String from;
  final String to;
  final double progress;
  final TextStyle style;
  final double height;

  /// Room for the wider of the two glyphs.
  final double faceWidth;

  const _RollingChar({
    required this.from,
    required this.to,
    required this.progress,
    required this.style,
    required this.height,
    required this.faceWidth,
  });

  @override
  Widget build(BuildContext context) {
    final appearing = from.trim().isEmpty;
    final leaving = to.trim().isEmpty;

    // Glyphs sit at the start of their slot, which is the pen position a
    // plain Text draws them at.
    if (from == to) {
      return OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: faceWidth,
        child: Text(to, style: style, maxLines: 1, softWrap: false),
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
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(char, style: style, maxLines: 1, softWrap: false),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: faceWidth,
        maxWidth: faceWidth,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!appearing) face(from, -progress),
            if (!leaving) face(to, 1 - progress),
          ],
        ),
      ),
    );
  }
}

/// Animates a 0..1 ratio to its new value, starting from 0 on first build so
/// bars fill in when a screen opens.
class AnimatedRatio extends StatelessWidget {
  /// Target ratio, 0..1.
  final double value;

  /// Builds with the current animated value.
  final Widget Function(BuildContext context, double value) builder;

  /// Length of the animation.
  final Duration duration;

  /// Creates a [AnimatedRatio].
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
  /// Visible share of [child] from the start edge, 0..1.
  final double fraction;

  /// The clipped content.
  final Widget child;

  /// Creates a [RevealClip].
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

/// Clips to the leading [fraction] of the width (reading direction aware).
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
