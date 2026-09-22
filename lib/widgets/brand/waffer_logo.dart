import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

/// Official Waffer mark. The main wallet square is centered; the flap
/// and clasp sit outside that square. Edges stay transparent.
class WafferLogo extends StatelessWidget {
  static const assetPath = 'assets/brand/waffer_logo.png';

  final double size;

  const WafferLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      semanticLabel: 'شعار وفّر',
    );
  }
}

/// Shown while the app is resolving theme and auth state.
/// Uses the same background as the rest of the app.
class WafferSplash extends StatelessWidget {
  final bool followPlatformBrightness;

  const WafferSplash({
    super.key,
    this.followPlatformBrightness = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = followPlatformBrightness
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: background,
      body: const SafeArea(
        child: Center(
          child: WafferLogo(size: 84),
        ),
      ),
    );
  }
}
