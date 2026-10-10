// Translucent "glass" card surface. Uses a tinted fill only — no BackdropFilter —
// so scrolling stays smooth; glass is a translucent color, not a live blur.
import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// Which palette token tints the glass fill.
enum GlassColorType { accent, background, surface, textPrimary, textSecondary }

/// Rounded translucent card with a light border and soft shadow.
///
/// Intentionally skips [BackdropFilter]: blurring whatever sits behind every
/// card caused scroll jank. The look comes from a translucent palette fill.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  /// Uneven corners when a circular [borderRadius] is not enough (e.g. sheets).
  final BorderRadius? radius;

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
    this.colorType = GlassColorType.accent,
    this.tintOpacity = 0.8,
  });

  /// Maps [colorType] to the matching token on the active palette.
  Color _resolveColor(AppPalette palette) {
    switch (colorType) {
      case GlassColorType.accent:
        return palette.accent;
      case GlassColorType.background:
        return palette.background;
      case GlassColorType.surface:
        return palette.surface;
      case GlassColorType.textPrimary:
        return palette.textPrimary;
      case GlassColorType.textSecondary:
        return palette.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color baseColor = _resolveColor(palette);
    final Color borderColor = palette.textPrimary;
    final BorderRadius shape = radius ?? BorderRadius.circular(borderRadius);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: tintOpacity),
        borderRadius: shape,
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
      child: child,
    );
  }
}
