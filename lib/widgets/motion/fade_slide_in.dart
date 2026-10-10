import 'dart:async';

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';

// Fades a child in while it rises a few pixels, once, when it is first
// built. [delay] staggers siblings; [enabled] false shows it at rest.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final bool enabled;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.enabled = true,
  });

  // Delay for the [index]th item of a list, capped so long lists don't wait.
  static Duration staggerFor(int index) =>
      Duration(milliseconds: 45 * index.clamp(0, 6));

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  static const double _rise = 14;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );
  Timer? _delayTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (!widget.enabled || AppMotion.reduced(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, _rise * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
