// Profile card: a brass balance scale weighing what the user saved against
// what they spent lately. It shows only the overall state (a one-word
// verdict and a short line), never amounts. The beam swings to its new
// angle on a spring and the pans sway a little as it moves.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:waffr/core/insights/money_balance.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/widgets/containers/glass.dart';

class BalanceScaleCard extends StatelessWidget {
  final MoneyBalance balance;

  const BalanceScaleCard({super.key, required this.balance});

  void _explain(BuildContext context) {
    showAppInfoDialog(
      context,
      title: 'ميزانك',
      message:
          'يزن الميزان ما وفّرته مقابل ما صرفته مؤخراً، ويميل نحو الكفة الأثقل. '
          'كلما وفّرت أكثر اعتدل الميزان ومال نحو التوفير.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final verdictColor = switch (balance.state) {
      BalanceState.balanced || BalanceState.savingHeavy => palette.accent,
      BalanceState.spendingHeavy => AppColors.warningOf(context),
      _ => palette.textSecondary,
    };

    TextStyle text(Color color, double size, FontWeight weight) => TextStyle(
          fontFamily: 'Outfit',
          fontFamilyFallback: const ['Tajawal'],
          fontSize: size,
          fontWeight: weight,
          color: color,
        );

    return Semantics(
      button: true,
      label: 'ميزانك: ${balance.verdict}. ${balance.message}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _explain(context),
        behavior: HitTestBehavior.opaque,
        child: GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title and the one-word verdict.
              Row(
                children: [
                  Text(
                    'ميزانك',
                    style: text(palette.textPrimary, 15, FontWeight.w800),
                  ),
                  const Spacer(),
                  if (balance.state != BalanceState.empty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        balance.verdict,
                        style: text(verdictColor, 12.5, FontWeight.w800),
                      ),
                    ),
                ],
              ),

              // The scale, with the pan names under the pans.
              SizedBox(
                height: 196,
                child: Stack(
                  children: [
                    Positioned.fill(child: _AnimatedScale(balance: balance)),
                    Align(
                      alignment: const AlignmentDirectional(-0.74, 1),
                      child: Text(
                        'التوفير',
                        style: text(palette.accent, 12.5, FontWeight.w800),
                      ),
                    ),
                    Align(
                      alignment: const AlignmentDirectional(0.74, 1),
                      child: Text(
                        'الصرف',
                        style: text(palette.textSecondary, 12.5, FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Text(
                balance.message,
                textAlign: TextAlign.center,
                style: text(palette.textPrimary, 13, FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Drives the beam angle with a damped spring. Its speed also tips the
// pans a little the other way, like real hanging pans.
class _AnimatedScale extends StatefulWidget {
  final MoneyBalance balance;

  const _AnimatedScale({required this.balance});

  @override
  State<_AnimatedScale> createState() => _AnimatedScaleState();
}

class _AnimatedScaleState extends State<_AnimatedScale>
    with SingleTickerProviderStateMixin {
  // Steepest beam angle, reached at the ends of the tilt range.
  static const double _maxAngle = 12 * math.pi / 180;

  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 70,
    damping: 6,
  );

  late final AnimationController _angle = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  double get _target => widget.balance.tilt * _maxAngle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First build: swing in from level.
    if (_angle.value == 0 && !_angle.isAnimating) _settle();
  }

  @override
  void didUpdateWidget(_AnimatedScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.balance.tilt != widget.balance.tilt) _settle();
  }

  void _settle() {
    if (AppMotion.reduced(context)) {
      _angle.value = _target;
      return;
    }
    _angle.animateWith(
      SpringSimulation(_spring, _angle.value, _target, _angle.velocity),
    );
  }

  @override
  void dispose() {
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ScalePainter(
          angle: _angle,
          savedLoad: widget.balance.savedLoad,
          spentLoad: widget.balance.spentLoad,
          rtl: Directionality.of(context) == TextDirection.rtl,
          jewel: palette.accent,
          isDark: isDark,
        ),
      ),
    );
  }
}

// A brass scale: stepped base, turned pillar with a finial, tapered beam,
// chains, and two dishes holding stacks of coins. The saving pan is on the
// reading-start side; a positive angle lowers it.
class _ScalePainter extends CustomPainter {
  final AnimationController angle;
  final double savedLoad;
  final double spentLoad;
  final bool rtl;
  final Color jewel;
  final bool isDark;

  _ScalePainter({
    required this.angle,
    required this.savedLoad,
    required this.spentLoad,
    required this.rtl,
    required this.jewel,
    required this.isDark,
  }) : super(repaint: angle);

  // Brass, light to dark.
  static const Color _brassLight = Color(0xFFF1DDA8);
  static const Color _brass = Color(0xFFCDA65C);
  static const Color _brassDark = Color(0xFF8A6631);

  // Coin faces for each pan.
  static const List<Color> _greenCoin = [Color(0xFF8FD3A0), Color(0xFF2F7A4A)];
  static const List<Color> _copperCoin = [Color(0xFFF0C08E), Color(0xFFA9683A)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - 22; // room for the pan names under the scale
    final cx = w / 2;
    final pivot = Offset(cx, h * 0.2);

    _drawStand(canvas, cx, pivot, h, w);

    // Beam. With RTL the saving pan is on the right, so lowering it turns
    // the beam clockwise; in LTR it is on the left and the turn flips.
    final theta = rtl ? angle.value : -angle.value;
    final half = w * 0.34;
    final along = Offset(math.cos(theta), math.sin(theta));
    final rightEnd = pivot + along * half;
    final leftEnd = pivot - along * half;

    // The pans lag behind the beam: a turning beam swings them back.
    final sway = (-angle.velocity * 0.05).clamp(-0.12, 0.12);
    final chain = h * 0.36;
    final savingEnd = rtl ? rightEnd : leftEnd;
    final spendingEnd = rtl ? leftEnd : rightEnd;
    _drawPan(canvas, savingEnd, chain, w, sway, _greenCoin, savedLoad);
    _drawPan(canvas, spendingEnd, chain, w, sway, _copperCoin, spentLoad);

    _drawBeam(canvas, pivot, theta, half);
    _drawPivot(canvas, pivot);
  }

  // Ground shadow, stepped base, tapered pillar, collar, and finial.
  void _drawStand(Canvas canvas, double cx, Offset pivot, double h, double w) {
    final ground = h + 14;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ground), width: w * 0.42, height: 12),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final lower = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, ground - 6), width: w * 0.32, height: 11),
      const Radius.circular(5),
    );
    final upper = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, ground - 15), width: w * 0.2, height: 9),
      const Radius.circular(4),
    );
    canvas.drawRRect(lower, _metalVertical(lower.outerRect));
    canvas.drawRRect(upper, _metalVertical(upper.outerRect));

    // Pillar, slightly wider at the foot, shaded like a cylinder.
    final top = pivot.dy + 4;
    final foot = ground - 19;
    final pillar = Path()
      ..moveTo(cx - 3.5, top)
      ..lineTo(cx + 3.5, top)
      ..lineTo(cx + 6, foot)
      ..lineTo(cx - 6, foot)
      ..close();
    canvas.drawPath(pillar, _metalHorizontal(Rect.fromLTRB(cx - 6, top, cx + 6, foot)));

    // Collar where the pillar meets the base.
    final collar = Rect.fromCenter(center: Offset(cx, foot), width: 18, height: 6);
    canvas.drawOval(collar, _metalVertical(collar));

    // Finial above the pivot.
    canvas.drawLine(
      pivot,
      pivot.translate(0, -12),
      Paint()
        ..color = _brassDark
        ..strokeWidth = 2.5,
    );
    _sphere(canvas, pivot.translate(0, -15), 5.5);
  }

  // A beam thick in the middle and thin at the ends, with ball caps.
  void _drawBeam(Canvas canvas, Offset pivot, double theta, double half) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(theta);
    final beam = Path()
      ..moveTo(-half, -2)
      ..quadraticBezierTo(0, -6.5, half, -2)
      ..lineTo(half, 2)
      ..quadraticBezierTo(0, 6.5, -half, 2)
      ..close();
    canvas.drawPath(beam, _metalVertical(Rect.fromLTRB(-half, -6.5, half, 6.5)));
    canvas.restore();

    final along = Offset(math.cos(theta), math.sin(theta));
    _sphere(canvas, pivot + along * half, 4.2);
    _sphere(canvas, pivot - along * half, 4.2);
  }

  // Brass hub with the accent jewel in the middle.
  void _drawPivot(Canvas canvas, Offset pivot) {
    _sphere(canvas, pivot, 9);
    canvas.drawCircle(pivot, 4.2, Paint()..color = jewel);
    canvas.drawCircle(
      pivot.translate(-1.3, -1.3),
      1.4,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
  }

  // Hook ring, three chains, a dish seen slightly from above, and coins.
  void _drawPan(
    Canvas canvas,
    Offset end,
    double chain,
    double w,
    double sway,
    List<Color> coin,
    double load,
  ) {
    final ring = end.translate(0, 7);
    canvas.drawCircle(
      ring,
      3.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _brassDark,
    );

    canvas.save();
    canvas.translate(ring.dx, ring.dy);
    canvas.rotate(sway);

    final panWidth = w * 0.27;
    final rimHeight = panWidth * 0.24;
    final rim = Rect.fromCenter(
      center: Offset(0, chain),
      width: panWidth,
      height: rimHeight,
    );

    // Chains to the left and right of the rim and to its far edge.
    final link = Paint()
      ..color = _brassDark.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final point in [rim.centerLeft, rim.centerRight, rim.topCenter]) {
      _dashed(canvas, Offset.zero, point, link);
    }

    // Dish body under the rim.
    final body = Path()
      ..moveTo(rim.left, rim.center.dy)
      ..quadraticBezierTo(0, rim.center.dy + panWidth * 0.42, rim.right, rim.center.dy)
      ..close();
    canvas.drawPath(body, _metalVertical(Rect.fromLTRB(rim.left, rim.top, rim.right, rim.bottom + panWidth * 0.3)));

    // Inside of the dish.
    canvas.drawOval(
      rim.deflate(1.5),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_brassDark, _brass],
        ).createShader(rim),
    );

    // Coins, stacked a little unevenly so it reads as a real pile.
    final coins = load <= 0 ? 0 : (1 + load * 5).round();
    final coinWidth = panWidth * 0.46;
    final coinHeight = coinWidth * 0.3;
    for (var i = 0; i < coins; i++) {
      final jitter = (i.isEven ? 1 : -1) * (i % 3) * 1.4;
      final center = Offset(jitter, rim.center.dy - i * 4.2);
      final face = Rect.fromCenter(center: center, width: coinWidth, height: coinHeight);
      canvas.drawOval(face.shift(const Offset(0, 2.6)), Paint()..color = coin[1]);
      canvas.drawOval(
        face,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: coin,
          ).createShader(face),
      );
      canvas.drawOval(
        face.deflate(2.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.white.withValues(alpha: 0.45),
      );
    }

    // Front lip, drawn last so it sits in front of the coins.
    final lip = Path()..addArc(rim, 0, math.pi);
    canvas.drawPath(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = _brassLight,
    );

    canvas.restore();
  }

  // A small shaded brass ball.
  void _sphere(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 0.9,
          colors: [_brassLight, _brass, _brassDark],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  // A chain: short links with gaps between them.
  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    final length = delta.distance;
    if (length <= 0) return;
    final step = delta / length;
    const dash = 3.0;
    const gap = 2.2;
    for (var t = 0.0; t < length; t += dash + gap) {
      final a = from + step * t;
      final b = from + step * math.min(t + dash, length);
      canvas.drawLine(a, b, paint);
    }
  }

  Paint _metalVertical(Rect rect) => Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_brassLight, _brass, _brassDark],
      stops: [0, 0.45, 1],
    ).createShader(rect);

  Paint _metalHorizontal(Rect rect) => Paint()
    ..shader = const LinearGradient(
      colors: [_brassDark, _brassLight, _brass, _brassDark],
      stops: [0, 0.35, 0.6, 1],
    ).createShader(rect);

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.savedLoad != savedLoad ||
      old.spentLoad != spentLoad ||
      old.rtl != rtl ||
      old.jewel != jewel ||
      old.isDark != isDark;
}
