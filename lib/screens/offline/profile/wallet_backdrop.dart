// The Waffr wallet drawn large and faint behind the profile's lower cards.
// The wallet is the logo artwork with its mouth removed; the mouth is a
// vector path redrawn on top (waffr_mouth.dart), so only the smile changes
// with the wallet's mood and it morphs between poses instead of swapping
// images. While the tab is on screen the wallet breathes slowly.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/brand/waffr_mouth.dart';

/// Fills its box and hangs the wallet from the box's bottom edge. Fades in
/// once the artwork is cached and a [form] is known.
class WalletBackdrop extends StatefulWidget {
  /// The visible page; the wallet is sized from it.
  final Size page;

  /// Drives the smile. Null keeps the wallet hidden until the first read.
  final SmileForm? form;

  /// False while another tab is showing, so the idle motion stops.
  final bool active;

  /// Creates a [WalletBackdrop].
  const WalletBackdrop({
    super.key,
    required this.page,
    required this.form,
    required this.active,
  });

  /// The green strokes of waffr_logo.png (no mouth, no cream fill), blurred
  /// (sigma 6 at 1440 px) and faded out over the top 40%. The cream is left
  /// out so the wallet's body takes the page color in both themes.
  static const _asset = AssetImage('assets/brand/waffr_logo_backdrop.png');

  /// Blur of the artwork as a share of its size, matched by the mouth.
  static const double _blur = 6 / 1440;

  /// Share of the mark that hangs below the bottom of the page.
  static const double _sink = 0.08;

  /// Bigger than the page is wide, and scaled with the height so the smile
  /// lands in the free space under the cards on short and tall phones alike.
  static double _sizeFor(Size page) => math.min(
    math.max(page.height * 0.82, page.width * 1.35),
    math.min(page.width * 1.8, page.height * 1.2),
  );

  /// Bottom space the content should keep so the widest smile shows below
  /// its last card.
  static double contentClearance(Size page) {
    final size = _sizeFor(page);
    return size * (1 - MouthShape.topmost - _sink) + 20;
  }

  @override
  State<WalletBackdrop> createState() => _WalletBackdropState();
}

/// State of [WalletBackdrop]. Owns the fade-in and breathing controllers
/// and precaches the artwork once.
class _WalletBackdropState extends State<WalletBackdrop>
    with TickerProviderStateMixin {
  /// The logo's own green. Dark pages use the dark accent instead.
  static const Color _ink = Color(0xFF135239);

  /// Fade-in when the wallet first becomes visible.
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// Eased fade-in, mapped to the artwork and mouth opacity.
  late final CurvedAnimation _shown = CurvedAnimation(
    parent: _appear,
    curve: AppMotion.enter,
  );

  /// One slow inhale and exhale.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  /// The artwork finished precaching.
  bool _imageReady = false;

  /// Precache was started (it runs once).
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      precacheImage(WalletBackdrop._asset, context).then((_) {
        if (!mounted) return;
        setState(() => _imageReady = true);
        _sync();
      });
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant WalletBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Shown only once the artwork is ready and a form is known.
  bool get _visible => _imageReady && widget.form != null;

  /// Starts or stops the fade-in and breathing to match visibility, the
  /// active tab and the motion settings.
  void _sync() {
    if (!mounted) return;
    final reduced = AppMotion.reduced(context);
    if (!_visible) {
      _breath.stop();
      return;
    }

    if (reduced) {
      _appear.value = 1;
    } else if (_appear.isDismissed) {
      _appear.forward();
    }

    if (widget.active && AppMotion.enabled(context)) {
      if (!_breath.isAnimating) _breath.repeat();
    } else {
      _breath.stop();
      if (reduced) _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    _appear.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    if (!_visible || form == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppPalette.of(context).accent : _ink;
    final opacity = _shown.drive(
      Tween<double>(begin: 0, end: isDark ? 0.12 : 0.14),
    );
    final size = WalletBackdrop._sizeFor(widget.page);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = constraints.biggest;
            // Artwork plus the morphing mouth, isolated from the breathing transform.
            final mark = RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: WalletBackdrop._asset,
                    fit: BoxFit.fill,
                    color: ink,
                    colorBlendMode: BlendMode.srcIn,
                    opacity: opacity,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                  TweenAnimationBuilder<MouthShape>(
                    tween: MouthTween(end: MouthShape.of(form)),
                    duration: AppMotion.of(
                      context,
                      const Duration(milliseconds: 900),
                    ),
                    curve: AppMotion.standard,
                    builder: (context, mouth, _) => CustomPaint(
                      painter: MouthPainter(
                        shape: mouth,
                        opacity: opacity,
                        color: ink,
                        blur: WalletBackdrop._blur,
                      ),
                    ),
                  ),
                ],
              ),
            );

            // The smile is centered; the clasp runs off the right edge.
            // Positions are absolute, so the mark is not mirrored in RTL.
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: box.width / 2 - MouthShape.centerX * size,
                  top: box.height - size * (1 - WalletBackdrop._sink),
                  width: size,
                  height: size,
                  child: AnimatedBuilder(
                    animation: _breath,
                    child: mark,
                    builder: (context, child) {
                      // 0 at rest, 1 at the top of the breath.
                      final t = (1 - math.cos(_breath.value * 2 * math.pi)) / 2;
                      // Grow from under the mouth so the smile stays put.
                      return Transform(
                        alignment: const Alignment(
                          MouthShape.centerX * 2 - 1,
                          1,
                        ),
                        transform: Matrix4.translationValues(0, -3 * t, 0)
                          ..scaleByDouble(1 + 0.012 * t, 1 + 0.012 * t, 1, 1),
                        child: child,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
