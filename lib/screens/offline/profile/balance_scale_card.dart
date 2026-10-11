// Profile card: a balance scale weighing what the user saved against what
// they spent over the last 30 days. The beam is level at the target saving
// share, so it moves as habits change rather than with every purchase.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/money_balance.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/widgets/containers/glass.dart';

class BalanceScaleCard extends StatelessWidget {
  final MoneyBalance balance;

  const BalanceScaleCard({super.key, required this.balance});

  // Steepest beam angle, reached at twice (or zero) the target share.
  static const double _maxAngle = 13 * math.pi / 180;

  void _explain(BuildContext context) {
    showAppInfoDialog(
      context,
      title: 'ميزانك',
      message:
          'يزن الميزان ما وفّرته مقابل ما صرفته خلال آخر ${MoneyBalance.windowDays} يوماً. '
          'يستوي عندما يذهب نحو ${(MoneyBalance.target * 100).round()}% من حركة مالك إلى التوفير، '
          'ويميل نحو الكفة الأثقل. السحب من التوفير يُخصم من كفة التوفير.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final stateColor = switch (balance.state) {
      BalanceState.balanced || BalanceState.savingHeavy => palette.accent,
      BalanceState.spendingHeavy => AppColors.warningOf(context),
      _ => palette.textSecondary,
    };
    final trend = balance.trendText;

    TextStyle text(Color color, double size, FontWeight weight) => TextStyle(
          fontFamily: 'Outfit',
          fontFamilyFallback: const ['Tajawal'],
          fontSize: size,
          fontWeight: weight,
          color: color,
        );

    return GestureDetector(
      onTap: () => _explain(context),
      behavior: HitTestBehavior.opaque,
      child: GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'ميزانك',
                  style: text(palette.textPrimary, 15, FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    balance.title,
                    style: text(stateColor, 12, FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Text(
                  'آخر ${MoneyBalance.windowDays} يوماً',
                  style: text(palette.textSecondary, 11.5, FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: balance.tilt),
                duration: AppMotion.of(
                  context,
                  const Duration(milliseconds: 1400),
                ),
                curve: Curves.elasticOut,
                builder: (context, tilt, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _ScalePainter(
                    angle: tilt * _maxAngle,
                    savedWeight: _weight(balance.saved),
                    spentWeight: _weight(balance.spent),
                    rtl: Directionality.of(context) == TextDirection.rtl,
                    savingColor: palette.accent,
                    spendingColor: palette.textSecondary,
                    frameColor: palette.textPrimary.withValues(alpha: 0.55),
                    surface: palette.surface,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _PanLabel(
                    label: 'التوفير',
                    amount: balance.saved,
                    color: palette.accent,
                  ),
                ),
                Expanded(
                  child: _PanLabel(
                    label: 'الصرف',
                    amount: balance.spent,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              balance.caption,
              textAlign: TextAlign.center,
              style: text(palette.textPrimary, 12.5, FontWeight.w600),
            ),
            if (!balance.isEmpty) ...[
              const SizedBox(height: 3),
              Text(
                trend == null
                    ? 'نسبة التوفير ${balance.shareText}'
                    : 'نسبة التوفير ${balance.shareText} · $trend',
                textAlign: TextAlign.center,
                style: text(palette.textSecondary, 11.5, FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Coins in a pan: none for nothing, then up to five by its share.
  int _weight(double amount) {
    final total = balance.saved + balance.spent;
    if (amount <= 0 || total <= 0) return 0;
    return (amount / total * 5).ceil().clamp(1, 5);
  }
}

class _PanLabel extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _PanLabel({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontFamilyFallback: const ['Tajawal'],
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${formatMoney(amount)} $currencyLabel',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// Stand, beam, strings and two pans. The saving pan sits on the reading
// start side; a positive [angle] lowers it.
class _ScalePainter extends CustomPainter {
  final double angle;
  final int savedWeight;
  final int spentWeight;
  final bool rtl;
  final Color savingColor;
  final Color spendingColor;
  final Color frameColor;
  final Color surface;

  const _ScalePainter({
    required this.angle,
    required this.savedWeight,
    required this.spentWeight,
    required this.rtl,
    required this.savingColor,
    required this.spendingColor,
    required this.frameColor,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w / 2, h * 0.2);
    final frame = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    // Stand.
    final baseY = h * 0.97;
    canvas.drawLine(pivot, Offset(w / 2, baseY - 6), frame..strokeWidth = 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w / 2, baseY - 3), width: w * 0.22, height: 7),
        const Radius.circular(4),
      ),
      Paint()..color = frameColor,
    );

    // Beam. With RTL the saving pan is on the right; tilting it down means
    // turning clockwise. In LTR it is on the left, so the turn flips.
    final turn = rtl ? angle : -angle;
    final half = w * 0.33;
    final dx = half * math.cos(turn);
    final dy = half * math.sin(turn);
    final right = Offset(pivot.dx + dx, pivot.dy + dy);
    final left = Offset(pivot.dx - dx, pivot.dy - dy);
    canvas.drawLine(left, right, frame..strokeWidth = 5);

    final savingEnd = rtl ? right : left;
    final spendingEnd = rtl ? left : right;
    _pan(canvas, savingEnd, size, savingColor, savedWeight, frame);
    _pan(canvas, spendingEnd, size, spendingColor, spentWeight, frame);

    // Pivot cap.
    canvas.drawCircle(pivot, 7.5, Paint()..color = savingColor);
    canvas.drawCircle(pivot, 3, Paint()..color = surface);
  }

  void _pan(
    Canvas canvas,
    Offset hook,
    Size size,
    Color color,
    int coins,
    Paint frame,
  ) {
    final panWidth = size.width * 0.26;
    final rimY = hook.dy + size.height * 0.42;
    final leftRim = Offset(hook.dx - panWidth / 2, rimY);
    final rightRim = Offset(hook.dx + panWidth / 2, rimY);

    final string = Paint()
      ..color = frame.color.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(hook, leftRim, string);
    canvas.drawLine(hook, rightRim, string);
    canvas.drawCircle(hook, 3, Paint()..color = frame.color);

    // Coin stack resting in the bowl.
    final coinWidth = panWidth * 0.5;
    const coinHeight = 7.0;
    for (var i = 0; i < coins; i++) {
      final center = Offset(hook.dx, rimY - 3 - i * 5.5);
      final rect = Rect.fromCenter(
        center: center,
        width: coinWidth,
        height: coinHeight,
      );
      canvas.drawOval(rect, Paint()..color = color);
      canvas.drawOval(
        rect.deflate(1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }

    // Bowl.
    final bowl = Path()
      ..moveTo(leftRim.dx, leftRim.dy)
      ..quadraticBezierTo(hook.dx, rimY + 26, rightRim.dx, rightRim.dy)
      ..close();
    canvas.drawPath(bowl, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(
      bowl,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.angle != angle ||
      old.savedWeight != savedWeight ||
      old.spentWeight != spentWeight ||
      old.rtl != rtl ||
      old.savingColor != savingColor ||
      old.spendingColor != spendingColor ||
      old.frameColor != frameColor ||
      old.surface != surface;
}
