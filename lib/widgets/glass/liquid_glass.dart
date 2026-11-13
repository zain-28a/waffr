// Liquid glass: the one glass material for floating chrome (header, bottom
// bar, selectors, sheets). It bends what is behind it near its rounded edge,
// lightly blurs and saturates the middle, and catches light along its rim.
//
// Layers, back to front: backdrop blur and saturation, edge refraction
// (shaders/liquid_glass.frag, Impeller only), a thin surface tint, rim light
// and sheen, then the child, which is never distorted.
//
// Where the shader filter is unsupported (non-Impeller renderers, web) the
// same widget still draws blur, tint and light, so glass never disappears.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// Optical settings of a glass surface, in logical pixels.
@immutable
class GlassPreset {
  /// Backdrop blur sigma.
  final double blur;

  /// Largest sideways shift at the edge.
  final double refraction;

  /// Bezel width: how far in from the edge the curve reaches.
  final double thickness;

  /// Alpha of the surface tint.
  final double opacity;

  /// Backdrop saturation (1 leaves it unchanged).
  final double saturation;

  /// Strength of rim light and sheen, 0..1.
  final double specular;

  /// Red/blue split as a share of the refraction.
  final double chroma;

  /// A preset.
  const GlassPreset({
    required this.blur,
    required this.refraction,
    required this.thickness,
    required this.opacity,
    required this.saturation,
    required this.specular,
    required this.chroma,
  });

  /// Clarity first: almost no blur, a crisp lens edge.
  static const crystal = GlassPreset(
    blur: 1.5,
    refraction: 18,
    thickness: 12,
    opacity: 0.04,
    saturation: 1.12,
    specular: 0.6,
    chroma: 0.035,
  );

  /// The signature look: floating bars and pills.
  static const liquid = GlassPreset(
    blur: 4,
    refraction: 20,
    thickness: 16,
    opacity: 0.14,
    saturation: 1.4,
    specular: 0.85,
    chroma: 0.06,
  );

  /// Readability first: sheets and anything with body text on it.
  static const frosted = GlassPreset(
    blur: 22,
    refraction: 14,
    thickness: 12,
    opacity: 0.72,
    saturation: 1.5,
    specular: 0.5,
    chroma: 0.02,
  );

  /// A copy with a different surface [opacity].
  GlassPreset withOpacity(double opacity) => GlassPreset(
    blur: blur,
    refraction: refraction,
    thickness: thickness,
    opacity: opacity,
    saturation: saturation,
    specular: specular,
    chroma: chroma,
  );
}

/// Ancestors that fade or move their subtree through an offscreen layer
/// (a fade-through, a hidden pager) turn [refract] off while they animate:
/// the lens needs a settled position on screen. Blur, tint and light stay.
class LiquidGlassScope extends InheritedWidget {
  /// False pauses edge refraction below this widget.
  final bool refract;

  /// Creates a [LiquidGlassScope].
  const LiquidGlassScope({
    super.key,
    required this.refract,
    required super.child,
  });

  /// Whether refraction is allowed at [context].
  static bool refractOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidGlassScope>()?.refract ??
      true;

  @override
  bool updateShouldNotify(LiquidGlassScope oldWidget) =>
      oldWidget.refract != refract;
}

/// Loads the lens shader once for the whole app.
class LiquidGlassShader {
  LiquidGlassShader._();

  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Set to true in tests to force the blur-only path.
  @visibleForTesting
  static bool debugDisable = false;

  /// The compiled lens program, or null while loading or unsupported.
  static ui.FragmentProgram? get program => debugDisable ? null : _program;

  /// True when this renderer can run a shader as a backdrop filter.
  static bool get supported =>
      !debugDisable && !kIsWeb && ui.ImageFilter.isShaderFilterSupported;

  /// Starts loading the shader; safe to call many times.
  static Future<void> ensureLoaded() {
    if (!supported) return Future<void>.value();
    return _loading ??=
        ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag')
            .then<void>((program) => _program = program)
            .catchError((Object error) {
              debugPrint('Liquid glass shader unavailable: $error');
            });
  }
}

/// A liquid-glass surface behind [child].
///
/// Place it in a [Stack] above the content it should show through. Corners
/// use one [radius]; [bleed] pushes the optical edge outside the widget on
/// the given sides, for surfaces attached to a screen edge (a header has no
/// top bezel, a sheet no bottom one).
class LiquidGlass extends StatefulWidget {
  /// Foreground content; drawn sharp, on top of the glass.
  final Widget child;

  /// Corner radius.
  final BorderRadius radius;

  /// Optical settings.
  final GlassPreset preset;

  /// Surface tint; defaults to the theme surface.
  final Color? tint;

  /// Sides on which the glass continues past the widget (no bezel there).
  final EdgeInsets bleed;

  /// Draws the soft drop shadow that lifts floating chrome.
  final bool shadow;

  /// Where the light comes from; rim and sheen follow it.
  final Alignment light;

  /// Creates a [LiquidGlass].
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(28)),
    this.preset = GlassPreset.liquid,
    this.tint,
    this.bleed = EdgeInsets.zero,
    this.shadow = true,
    this.light = const Alignment(-0.6, -1),
  });

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass>
    with SingleTickerProviderStateMixin {
  /// 0 while the surface is moving or covered by a transition, 1 at rest.
  /// Scales the refraction so it fades in instead of popping.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  ui.FragmentShader? _shader;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    if (LiquidGlassShader.supported && LiquidGlassShader.program == null) {
      LiquidGlassShader.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.animation?.removeStatusListener(_onRoute);
      _route?.secondaryAnimation?.removeStatusListener(_onRoute);
      _route = route;
      route?.animation?.addStatusListener(_onRoute);
      route?.secondaryAnimation?.addStatusListener(_onRoute);
    }
    _syncSettle();
  }

  void _onRoute(AnimationStatus _) => _syncSettle();

  /// The lens is only exact while its place on screen is settled.
  bool get _atRest {
    if (!LiquidGlassScope.refractOf(context)) return false;
    final route = _route;
    if (route == null) return true;
    final entering = route.animation?.status ?? AnimationStatus.completed;
    final covered =
        route.secondaryAnimation?.status ?? AnimationStatus.dismissed;
    return entering == AnimationStatus.completed &&
        covered == AnimationStatus.dismissed;
  }

  void _syncSettle() {
    if (!mounted) return;
    if (_atRest) {
      if (AppMotion.reduced(context)) {
        _settle.value = 1;
      } else if (_settle.status != AnimationStatus.completed &&
          _settle.status != AnimationStatus.forward) {
        _settle.forward();
      }
    } else {
      _settle.value = 0;
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onRoute);
    _route?.secondaryAnimation?.removeStatusListener(_onRoute);
    _settle.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preset = widget.preset;
    // The closest signal Flutter has for "reduce transparency".
    final solid = MediaQuery.highContrastOf(context);
    final tint = (widget.tint ?? palette.surface).withValues(
      alpha: solid ? 0.94 : preset.opacity.clamp(0.0, 1.0),
    );

    final program = LiquidGlassShader.program;
    if (program != null && _shader == null) {
      _shader = program.fragmentShader();
    }

    Widget glass = _GlassLens(
      radius: widget.radius,
      bleed: widget.bleed,
      preset: preset,
      shader: solid ? null : _shader,
      settle: _settle,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      child: CustomPaint(
        foregroundPainter: _GlassLightPainter(
          radius: widget.radius,
          bleed: widget.bleed,
          light: widget.light,
          specular: preset.specular,
          isDark: isDark,
        ),
        child: ColoredBox(color: tint, child: widget.child),
      ),
    );

    if (widget.shadow) {
      glass = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: glass,
      );
    }
    return glass;
  }
}

/// Clips to the glass shape and filters the backdrop behind [child].
class _GlassLens extends SingleChildRenderObjectWidget {
  final BorderRadius radius;
  final EdgeInsets bleed;
  final GlassPreset preset;
  final ui.FragmentShader? shader;
  final Animation<double> settle;
  final double devicePixelRatio;

  const _GlassLens({
    required this.radius,
    required this.bleed,
    required this.preset,
    required this.shader,
    required this.settle,
    required this.devicePixelRatio,
    required super.child,
  });

  @override
  _RenderGlassLens createRenderObject(BuildContext context) => _RenderGlassLens(
    radius: radius,
    bleed: bleed,
    preset: preset,
    shader: shader,
    settle: settle,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderGlassLens renderObject) {
    renderObject
      ..radius = radius
      ..bleed = bleed
      ..preset = preset
      ..shader = shader
      ..settle = settle
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderGlassLens extends RenderProxyBox {
  _RenderGlassLens({
    required this._radius,
    required this._bleed,
    required this._preset,
    required this._shader,
    required this._settle,
    required this._devicePixelRatio,
  });

  /// Lenses on screen; one frame callback checks them all for movement the
  /// framework did not repaint (a parent transform, a slide).
  static final Set<_RenderGlassLens> _attached = {};
  static bool _watching = false;

  static void _watch(Duration _) {
    for (final lens in _attached) {
      lens._repaintIfMoved();
    }
  }

  BorderRadius _radius;
  set radius(BorderRadius value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  EdgeInsets _bleed;
  set bleed(EdgeInsets value) {
    if (_bleed == value) return;
    _bleed = value;
    markNeedsPaint();
  }

  GlassPreset _preset;
  set preset(GlassPreset value) {
    if (identical(_preset, value)) return;
    _preset = value;
    markNeedsPaint();
  }

  ui.FragmentShader? _shader;
  set shader(ui.FragmentShader? value) {
    if (identical(_shader, value)) return;
    _shader = value;
    markNeedsPaint();
  }

  Animation<double> _settle;
  set settle(Animation<double> value) {
    if (identical(_settle, value)) return;
    if (attached) _settle.removeListener(markNeedsPaint);
    _settle = value;
    if (attached) _settle.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// Where the glass was on screen when it was last painted.
  Rect? _paintedRect;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _settle.addListener(markNeedsPaint);
    _attached.add(this);
    if (!_watching) {
      _watching = true;
      SchedulerBinding.instance.addPersistentFrameCallback(_watch);
    }
  }

  @override
  void detach() {
    _settle.removeListener(markNeedsPaint);
    _attached.remove(this);
    super.detach();
  }

  Rect _screenRect() =>
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  void _repaintIfMoved() {
    if (!attached || !hasSize || _shader == null) return;
    final painted = _paintedRect;
    if (painted == null) return;
    final now = _screenRect();
    if ((now.topLeft - painted.topLeft).distanceSquared > 0.01 ||
        (now.size.width - painted.size.width).abs() > 0.1 ||
        (now.size.height - painted.size.height).abs() > 0.1) {
      markNeedsPaint();
    }
  }

  static List<double> _saturation(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final ir = (1 - s) * r, ig = (1 - s) * g, ib = (1 - s) * b;
    return [
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0, //
      ir, ig, ib + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  ui.ImageFilter _filter() {
    final preset = _preset;
    ui.ImageFilter filter = ui.ImageFilter.compose(
      outer: ColorFilter.matrix(_saturation(preset.saturation)),
      inner: ui.ImageFilter.blur(
        sigmaX: preset.blur,
        sigmaY: preset.blur,
        tileMode: TileMode.mirror,
      ),
    );

    final shader = _shader;
    final strength = _settle.value;
    if (shader == null || strength <= 0) {
      _paintedRect = null;
      return filter;
    }

    final rect = _screenRect();
    _paintedRect = rect;
    final dpr = _devicePixelRatio;
    final optical = _bleed.inflateRect(rect);
    // The lens has one radius; surfaces attached to an edge round only the
    // free corners, so take the largest.
    final radius = [
      _radius.topLeft.x,
      _radius.topRight.x,
      _radius.bottomLeft.x,
      _radius.bottomRight.x,
    ].reduce((a, b) => a > b ? a : b);
    shader
      ..setFloat(2, optical.left * dpr)
      ..setFloat(3, optical.top * dpr)
      ..setFloat(4, optical.width * dpr)
      ..setFloat(5, optical.height * dpr)
      ..setFloat(6, radius * dpr)
      ..setFloat(7, preset.thickness * dpr)
      ..setFloat(8, preset.refraction * dpr * strength)
      ..setFloat(9, preset.chroma);
    filter = ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(shader),
      inner: filter,
    );
    return filter;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final bounds = offset & size;
    layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _radius.toRRect(Offset.zero & size),
      (context, offset) {
        final backdrop = BackdropFilterLayer(filter: _filter());
        context.pushLayer(
          backdrop,
          super.paint,
          offset,
          childPaintBounds: bounds,
        );
      },
      oldLayer: layer as ClipRRectLayer?,
    );
  }
}

/// Rim light, sheen and a bottom inner shade: the cues that sell a physical
/// edge. Pure gradients, no blur.
class _GlassLightPainter extends CustomPainter {
  final BorderRadius radius;
  final EdgeInsets bleed;
  final Alignment light;
  final double specular;
  final bool isDark;

  const _GlassLightPainter({
    required this.radius,
    required this.bleed,
    required this.light,
    required this.specular,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    // The optical outline; sides that bleed fall outside the clip.
    final corner = [
      radius.topLeft,
      radius.topRight,
      radius.bottomLeft,
      radius.bottomRight,
    ].reduce((a, b) => a.x > b.x ? a : b);
    final outline = RRect.fromRectAndRadius(
      bleed.inflateRect(rect),
      corner,
    ).deflate(0.5);
    final gain = specular * (isDark ? 0.55 : 1.0);
    Color white(double a) =>
        Colors.white.withValues(alpha: (a * gain).clamp(0.0, 1.0));
    final opposite = Alignment(-light.x, -light.y);

    // Sheen: a soft pool of light on the side facing the light.
    canvas.drawRRect(
      outline,
      Paint()
        ..shader = RadialGradient(
          center: light,
          radius: 1.2,
          colors: [white(0.16), white(0)],
        ).createShader(rect),
    );

    // Thickness: a faint shade gathering at the far edge.
    canvas.drawRRect(
      outline,
      Paint()
        ..shader = LinearGradient(
          begin: light,
          end: opposite,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: isDark ? 0.16 : 0.07),
          ],
          stops: const [0.72, 1],
        ).createShader(rect),
    );

    // Rim: bright toward the light, faint opposite. Never a uniform border.
    canvas.drawRRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: light,
          end: opposite,
          colors: [
            white(0.95),
            white(0.2),
            white(0.02),
            white(0.14),
            white(0.5),
          ],
          stops: const [0, 0.3, 0.5, 0.72, 1],
        ).createShader(rect),
    );

    // On light pages a hairline keeps the glass from melting into white.
    if (!isDark) {
      canvas.drawRRect(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.08),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassLightPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.bleed != bleed ||
      oldDelegate.light != light ||
      oldDelegate.specular != specular ||
      oldDelegate.isDark != isDark;
}
