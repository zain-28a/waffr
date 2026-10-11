// Proportional savings/spending split. Left is savings, right is spending.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/theme/app_motion.dart';

class SavingsSpendingBar extends StatelessWidget {
  final double savings;
  final double spending;
  final double height;

  const SavingsSpendingBar({
    super.key,
    required this.savings,
    required this.spending,
    this.height = 36,
  });

  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final safeSavings = savings.isFinite && savings > 0 ? savings : 0.0;
    final safeSpending = spending.isFinite && spending > 0 ? spending : 0.0;
    final total = safeSavings + safeSpending;
    final savingsShare = total <= 0 ? 0.0 : safeSavings / total;

    final label = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: savingsShare),
            duration: AppMotion.of(context, AppMotion.emphasized),
            curve: Curves.easeOutCubic,
            builder: (context, share, _) {
              return _SplitFill(
                height: height,
                radius: _radius,
                savingsShare: share,
                savingsColor: palette.accent,
                spendingColor: palette.textSecondary,
                dividerColor: palette.background,
                borderColor: palette.textPrimary.withValues(alpha: 0.1),
                emptyColor: palette.surface,
                showSpending: safeSpending > 0,
                showSavings: safeSavings > 0,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'التوفير',
                  textAlign: TextAlign.center,
                  style: label.copyWith(color: palette.accent),
                ),
              ),
              Expanded(
                child: Text(
                  'الصرف',
                  textAlign: TextAlign.center,
                  style: label.copyWith(color: palette.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplitFill extends StatelessWidget {
  final double height;
  final double radius;
  final double savingsShare;
  final Color savingsColor;
  final Color spendingColor;
  final Color dividerColor;
  final Color borderColor;
  final Color emptyColor;
  final bool showSavings;
  final bool showSpending;

  const _SplitFill({
    required this.height,
    required this.radius,
    required this.savingsShare,
    required this.savingsColor,
    required this.spendingColor,
    required this.dividerColor,
    required this.borderColor,
    required this.emptyColor,
    required this.showSavings,
    required this.showSpending,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    // Measured inside the 1px border so the fills always fit the track.
    return LayoutBuilder(
      builder: (context, outer) {
        final width = math.max(0.0, outer.maxWidth - 2);
        final savingsWidth =
            showSavings ? width * savingsShare.clamp(0.0, 1.0) : 0.0;
        final hasDivider = showSavings &&
            showSpending &&
            savingsWidth > 1 &&
            savingsWidth < width - 1;

        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: emptyColor),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (savingsWidth > 0)
                      SizedBox(
                        width: savingsWidth,
                        child: ColoredBox(color: savingsColor),
                      ),
                    if (showSpending)
                      Expanded(child: ColoredBox(color: spendingColor)),
                  ],
                ),
                if (hasDivider)
                  Positioned(
                    left: savingsWidth,
                    top: 0,
                    bottom: 0,
                    width: 1,
                    child: ColoredBox(color: dividerColor),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
