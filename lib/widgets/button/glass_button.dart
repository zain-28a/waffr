// Tappable glass surface with a brief press-scale animation.
// Visual chrome comes from GlassContainer (translucent fill, no BackdropFilter).
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
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
