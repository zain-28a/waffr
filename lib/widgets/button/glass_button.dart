import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/containers/glass.dart';

class GlassButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final GlassColorType colorType;
  final double tintOpacity;

  const GlassButton({
    super.key,
    required this.onTap,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 20,
    this.colorType = GlassColorType.accent,
    this.tintOpacity = 0.8,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    setState(() => _scale = 0.95);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  Color _resolveColor(bool isDark) {
    switch (widget.colorType) {
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

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          padding: widget.padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: widget.tintOpacity),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
