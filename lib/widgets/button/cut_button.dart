import 'package:flutter/material.dart';

class CutButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;

  const CutButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.backgroundColor,
    required this.textColor, required TextStyle style,
  });

  @override
  State<CutButton> createState() => _CutButtonState();
}

class _CutButtonState extends State<CutButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) => setState(() => _scale = 0.94);
  void _onTapUp(TapUpDetails details) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.bounceInOut,
        child:Container(width: 65 , height: 45,
            decoration: BoxDecoration(shape:BoxShape.rectangle, borderRadius: BorderRadius.all(Radius.circular(40)),
              color: widget.backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: widget.backgroundColor.withValues(alpha: 0.35),
                  blurRadius: 0.5,
                  offset: const Offset(0,2.6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 17,
                  fontWeight: FontWeight(400),
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ));
      
    
  }
}