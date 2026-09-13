import 'package:flutter/material.dart';

class RoundButtton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;

  const RoundButtton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.backgroundColor,
    required this.textColor, required TextStyle style,
  });

  @override
  State<RoundButtton> createState() => _RoundButttonState();
}

class _RoundButttonState extends State<RoundButtton> {
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
        curve: Curves.bounceIn,
        child:Container(width: 65 , height: 65,
            decoration: BoxDecoration(shape:BoxShape.circle, 
              color: widget.backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: widget.backgroundColor.withValues(alpha: 0.35),
                  blurRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 40,
                  fontWeight: FontWeight(400),
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ));
      
    
  }
}