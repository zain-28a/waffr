// Tappable glass surface that sinks on touch and springs back on release.
// Visual chrome comes from GlassContainer (translucent fill, no BackdropFilter).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/containers/glass.dart';

/// Pressable [GlassContainer] that scales slightly on tap.
///
/// Shares the same translucent fill as cards — no extra blur pass — so buttons
/// and glass surfaces stay consistent and cheap to paint.
class GlassButton extends StatefulWidget {
  final VoidCallback onTap;

  /// Optional second action on a long press.
  final VoidCallback? onLongPress;
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
    this.onLongPress,
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
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _onTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    // Sinks quickly on touch and springs back past its size on release.
    return GestureDetector(
      onTap: _onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _setPressed(false);
              widget.onLongPress!();
            },
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: AppMotion.of(
          context,
          _pressed
              ? const Duration(milliseconds: 90)
              : const Duration(milliseconds: 320),
        ),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: GlassContainer(
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          margin: widget.margin,
          borderRadius: widget.borderRadius,
          colorType: widget.colorType,
          tintOpacity: widget.tintOpacity,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Square glass icon button: the shell header actions (settings, bell) and
/// the balance card shortcuts share it so they look the same.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool dimmed;
  final bool showDot;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onLongPress,
    this.dimmed = false,
    this.showDot = false,
  });

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = dimmed ? palette.textSecondary : palette.accent;

    return Semantics(
      button: true,
      label: label,
      child: GlassButton(
        onTap: onPressed,
        onLongPress: onLongPress,
        width: size,
        height: size,
        padding: EdgeInsets.zero,
        borderRadius: 16,
        colorType: GlassColorType.surface,
        tintOpacity: 0.9,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.fast),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: 23,
                color: color,
              ),
            ),
            PositionedDirectional(
              top: 9,
              end: 10,
              child: AnimatedScale(
                scale: showDot ? 1 : 0,
                duration: AppMotion.of(context, AppMotion.fast),
                curve: showDot ? Curves.easeOutBack : Curves.easeIn,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.destructiveOf(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.surface, width: 1.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
