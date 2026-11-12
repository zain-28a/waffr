// The Waffr logo with a living mouth: the mouthless mark with the wallet's
// current smile drawn on top, morphing when the health score moves the
// face to another SmileForm. Used in the middle of the shell's top bar.

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/brand/waffr_mouth.dart';

/// The logo whose smile follows [WalletMood]. Before the first read it
/// shows the logo's own smile.
class WaffrMoodLogo extends StatefulWidget {
  /// The mark without a mouth (same artwork and size as the logo).
  static const assetPath = 'assets/brand/waffr_logo_mouthless.png';

  /// Width and height.
  final double size;

  /// Overrides [WalletMood] (previews and tests).
  final SmileForm? form;

  /// Creates a [WaffrMoodLogo].
  const WaffrMoodLogo({super.key, this.size = 44, this.form});

  @override
  State<WaffrMoodLogo> createState() => _WaffrMoodLogoState();
}

class _WaffrMoodLogoState extends State<WaffrMoodLogo> {
  /// The logo's own mouth color.
  static const Color _ink = Color(0xFF135239);

  final WalletMood _mood = WalletMood.instance;

  @override
  void initState() {
    super.initState();
    _mood.retain();
  }

  @override
  void dispose() {
    _mood.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return Semantics(
      image: true,
      label: 'شعار وفّر',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                WaffrMoodLogo.assetPath,
                width: size,
                height: size,
                cacheWidth: pixels,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
              ),
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: _mood,
                  builder: (context, _) {
                    final form =
                        widget.form ?? _mood.form ?? SmileForm.excellent;
                    return TweenAnimationBuilder<MouthShape>(
                      tween: MouthTween(end: MouthShape.of(form)),
                      duration: AppMotion.of(
                        context,
                        const Duration(milliseconds: 900),
                      ),
                      curve: AppMotion.standard,
                      builder: (context, mouth, _) => CustomPaint(
                        painter: MouthPainter(shape: mouth, color: _ink),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
