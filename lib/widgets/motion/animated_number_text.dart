import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';

// Text that counts from its previous value to a new one. The first build
// shows [value] directly; later changes roll the digits toward it.
class AnimatedNumberText extends StatelessWidget {
  final double value;
  final String Function(double value) format;
  final TextStyle? style;

  const AnimatedNumberText({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: AppMotion.of(context, AppMotion.countUp),
      curve: AppMotion.enter,
      builder: (context, current, _) => Text(format(current), style: style),
    );
  }
}
