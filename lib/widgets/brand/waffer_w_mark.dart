import 'package:flutter/material.dart';

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
    final base = Theme.of(context).textTheme.displayMedium;

    return Text(
      'W',
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: (base ?? const TextStyle()).copyWith(
        fontSize: size,
        color: color,
      ),
    );
  }
}
