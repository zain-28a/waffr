// Tappable glass surface that sinks on touch and springs back on release.
// Visual chrome comes from GlassContainer (translucent fill, no BackdropFilter).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffr/widgets/containers/glass.dart';

/// Pressable [GlassContainer] that scales slightly on tap.
///
/// Shares the same translucent fill as cards — no extra blur pass — so buttons
/// and glass surfaces stay consistent and cheap to paint.
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
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 90)
            : const Duration(milliseconds: 320),
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
