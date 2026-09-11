import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart'; // عدل المسار حسب مكان الملف عندك

enum GlassColorType { accent, background, surface, textPrimary, textSecondary }

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  /// يتجاوز [borderRadius] عند الحاجة لزوايا غير متساوية (مثل النوافذ السفلية).
  final BorderRadius? radius;

  final double blurSigma;
  final GlassColorType colorType;
  final double tintOpacity;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20,
    this.radius,
    this.blurSigma = 10,
    this.colorType = GlassColorType.accent,
    this.tintOpacity = 0.8,
  });

  Color _resolveColor(bool isDark) {
    switch (colorType) {
      case GlassColorType.accent:
        return isDark ? AppColors.darkAccent : AppColors.lightAccent;
      case GlassColorType.background:
        return isDark ? AppColors.darkBackground : AppColors.lightBackground;
      case GlassColorType.surface:
        return isDark ? AppColors.darkSurface : AppColors.lightSurface;
      case GlassColorType.textPrimary:
        return isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
      case GlassColorType.textSecondary:
        return isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color baseColor = _resolveColor(isDark);
    final Color borderColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final BorderRadius shape = radius ?? BorderRadius.circular(borderRadius);

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: tintOpacity),
              borderRadius: shape,
              border: Border.all(
                color: borderColor.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}