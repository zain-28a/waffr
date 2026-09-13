import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// حرف W بخط عنوان التطبيق، لأزرار الادخار والهدف والخطط.
class WafferWMark extends StatelessWidget {
  final double size;
  final Color color;

  const WafferWMark({
    super.key,
    required this.color,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      'W',
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        height: 1,
        color: color,
      ),
    );
  }
}
