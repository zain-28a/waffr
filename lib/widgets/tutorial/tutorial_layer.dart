// The tutorial's overlay: a dimmed screen with a clear, rounded window over
// the control the current step points at, and a message card beside it.
//
// It sits above the whole navigator (MaterialApp.builder), so it also
// covers sheets and pushed screens. Touches inside the window reach the
// real control underneath; touches elsewhere are held back while a step
// waits for that control. A hint over another screen draws only the card,
// at the bottom, and lets every touch through; hints for a sheet show
// inside the sheet itself (TutorialSheetHint), so nothing covers its
// fields or its save button.
//
// The window follows its target every frame while the tutorial runs, so
// scrolling and animations keep it in place. Dimming is a plain
// translucent fill, not a blur, to stay cheap on every frame.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/tutorial/tutorial_controller.dart';
import 'package:waffr/widgets/containers/glass.dart';

/// Puts the tutorial overlay above [child] (the app's navigator).
class TutorialLayer extends StatefulWidget {
  /// The app below the overlay.
  final Widget child;

  /// Creates a [TutorialLayer].
  const TutorialLayer({super.key, required this.child});

  @override
  State<TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends State<TutorialLayer>
    with SingleTickerProviderStateMixin {
  final TutorialController _controller = TutorialController.instance;

  /// Re-measures the target every frame while the tutorial is on screen.
  late final Ticker _ticker = createTicker(_measure);

  /// The target's rectangle in this layer's coordinates, or null.
  Rect? _hole;

  /// When the current step started waiting for its target to appear.
  Duration? _missingSince;

  String? _stepId;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStep);
    _onStep();
  }

  @override
  void dispose() {
    _controller.removeListener(_onStep);
    _ticker.dispose();
    super.dispose();
  }

  void _onStep() {
    final step = _controller.step;
    if (step == null) {
      if (_ticker.isActive) _ticker.stop();
      setState(() {
        _hole = null;
        _stepId = null;
      });
      return;
    }
    if (step.id != _stepId) {
      _stepId = step.id;
      _missingSince = null;
      _hole = null;
      // Bring the target into view once the step's tab has settled.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(step));
    }
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  Future<void> _reveal(TutorialStep step) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final target = step.target;
    if (!mounted || target == null || _controller.step != step) return;
    final targetContext = TutorialTargets.contextOf(target);
    if (targetContext == null || !targetContext.mounted) return;
    if (Scrollable.maybeOf(targetContext) == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.4,
      duration: AppMotion.of(context, AppMotion.medium),
      curve: AppMotion.standard,
    );
  }

  void _measure(Duration elapsed) {
    final step = _controller.step;
    final target = step?.target;
    if (step == null || target == null) {
      if (_hole != null) setState(() => _hole = null);
      return;
    }
    final global = TutorialTargets.rectOf(target);
    final box = context.findRenderObject();
    Rect? local;
    if (global != null && box is RenderBox && box.hasSize) {
      local = Rect.fromPoints(
        box.globalToLocal(global.topLeft),
        box.globalToLocal(global.bottomRight),
      );
      // A target scrolled under the screen edge counts as missing.
      if (!(Offset.zero & box.size).overlaps(local)) local = null;
    }
    if (local == null) {
      // The control is not on screen (no goal-creation button when goals
      // exist, a screen closed with the back button...). After a short
      // wait the step offers "next" so the tutorial never gets stuck.
      _missingSince ??= elapsed;
      if (elapsed - _missingSince! > const Duration(milliseconds: 1500)) {
        _controller.useFallback();
      }
    } else {
      _missingSince = null;
    }
    final changed =
        (local == null) != (_hole == null) ||
        (local != null &&
            _hole != null &&
            ((local.left - _hole!.left).abs() > 0.5 ||
                (local.top - _hole!.top).abs() > 0.5 ||
                (local.width - _hole!.width).abs() > 0.5 ||
                (local.height - _hole!.height).abs() > 0.5));
    if (changed) setState(() => _hole = local);
  }

  @override
  Widget build(BuildContext context) {
    final step = _controller.step;
    return Stack(
      fit: StackFit.expand,
      children: [widget.child, if (step != null) ..._overlay(context, step)],
    );
  }

  List<Widget> _overlay(BuildContext context, TutorialStep step) {
    final hole = _hole?.inflate(8);
    // Dim and hold back touches while a step points at a control that is
    // on screen; a hint (or a step whose control is missing) lets the
    // screen below be used.
    final spotlight = !step.isHint && hole != null;
    final fallback = !step.isHint && hole == null;
    final confirm = _controller.skipRequested;
    if (step.inline) return [if (confirm) ..._skipConfirm(context)];
    return [
      if (spotlight || fallback)
        Positioned.fill(
          child: _Barrier(
            hole: spotlight ? hole : null,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: spotlight ? hole : null,
                  dim: Colors.black.withValues(alpha: 0.55),
                  ring: AppPalette.of(context).accent,
                ),
              ),
            ),
          ),
        ),
      _positionedCard(context, step, spotlight ? hole : null),
      if (confirm) ..._skipConfirm(context),
    ];
  }

  Widget _positionedCard(BuildContext context, TutorialStep step, Rect? hole) {
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _TutorialCardLayout(
          hole: hole,
          padding: MediaQuery.paddingOf(context),
          requiresTargetTap: step.until != null && !_controller.waitsForNext,
          isHint: step.isHint,
        ),
        child: SingleChildScrollView(
          primary: false,
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            child: _MessageCard(
              key: ValueKey(step.id),
              step: step,
              showNext: _controller.waitsForNext,
              onNext: _controller.next,
              onSkip: _controller.requestSkip,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _skipConfirm(BuildContext context) {
    final palette = AppPalette.of(context);
    return [
      Positioned.fill(
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              type: MaterialType.transparency,
              child: GlassContainer(
                colorType: GlassColorType.surface,
                tintOpacity: 1,
                borderRadius: 26,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الخروج من الدليل؟',
                      style: _style(17, FontWeight.w800, palette.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ستخرج من الدليل التفاعلي ولن يظهر مرة أخرى تلقائياً. '
                      'بياناتك كما هي، ويمكنك إعادة الدليل في أي وقت من صفحة المساعدة.',
                      style: _style(
                        13.5,
                        FontWeight.w500,
                        palette.textSecondary,
                      ).copyWith(height: 1.55),
                    ),
                    const SizedBox(height: 16),
                    // Stacked, so both labels stay on one line at any width.
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        shape: const StadiumBorder(),
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: _controller.finish,
                      child: Text(
                        'الخروج من الدليل',
                        style: _style(
                          14.5,
                          FontWeight.w700,
                          palette.background,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _controller.cancelSkip,
                      child: Text(
                        'متابعة الدليل',
                        style: _style(14, FontWeight.w700, palette.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Places the measured card next to its target while keeping it on screen.
class _TutorialCardLayout extends SingleChildLayoutDelegate {
  final Rect? hole;
  final EdgeInsets padding;
  final bool requiresTargetTap;
  final bool isHint;

  const _TutorialCardLayout({
    required this.hole,
    required this.padding,
    required this.requiresTargetTap,
    required this.isHint,
  });

  static const double _margin = 16;
  static const double _gap = 14;

  double get _top => padding.top + _margin;
  double _bottom(double height) => height - padding.bottom - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = (constraints.maxWidth - 2 * _margin).clamp(0.0, 420.0);
    final bottom = _bottom(constraints.maxHeight);
    final target = hole;
    final maxHeight = requiresTargetTap && target != null
        ? math.max(target.top - _gap - _top, bottom - target.bottom - _gap)
        : bottom - _top;
    return BoxConstraints.tightFor(width: width)
        .copyWith(maxHeight: math.max(0.0, maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (size.width - childSize.width) / 2;
    final bottom = _bottom(size.height);
    final lowestTop = math.max(_top, bottom - childSize.height);
    final target = hole;
    if (target == null) {
      final top = isHint
          ? lowestTop
          : (size.height * 0.3).clamp(_top, lowestTop);
      return Offset(left, top);
    }

    final below = target.bottom + _gap;
    final above = target.top - _gap - childSize.height;
    if (below <= lowestTop) return Offset(left, math.max(_top, below));
    if (above >= _top) return Offset(left, math.min(lowestTop, above));
    // A large explanation target can fill the viewport. The card's own
    // button completes this step, so it can overlap the highlighted area.
    final top = target.top - _top > bottom - target.bottom ? _top : lowestTop;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_TutorialCardLayout oldDelegate) =>
      hole != oldDelegate.hole ||
      padding != oldDelegate.padding ||
      requiresTargetTap != oldDelegate.requiresTargetTap ||
      isHint != oldDelegate.isHint;
}

TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: 'Tajawal',
  fontFamilyFallback: const ['Outfit'],
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// The card with the step's counter, title, text and buttons.
class _MessageCard extends StatelessWidget {
  final TutorialStep step;
  final bool showNext;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _MessageCard({
    super.key,
    required this.step,
    required this.showNext,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        liveRegion: true,
        child: GlassContainer(
          colorType: GlassColorType.surface,
          tintOpacity: 1,
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'الخطوة ${step.topic} من $tutorialTopicCount',
                      style: _style(11.5, FontWeight.w700, palette.accent),
                    ),
                  ),
                  const Spacer(),
                  if (step.demo != null && step.isHint)
                    Text(
                      'وضع التجربة',
                      style: _style(
                        11.5,
                        FontWeight.w700,
                        palette.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                step.title,
                style: _style(16.5, FontWeight.w800, palette.textPrimary),
              ),
              const SizedBox(height: 5),
              Text(
                step.body,
                style: _style(
                  13.5,
                  FontWeight.w500,
                  palette.textSecondary,
                ).copyWith(height: 1.55),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      'تخطي الدليل',
                      style: _style(13, FontWeight.w600, palette.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  if (showNext)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      onPressed: onNext,
                      child: Text(
                        'التالي',
                        style: _style(14, FontWeight.w700, palette.background),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the dim layer with a rounded window and a thin ring around it.
class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final Color dim;
  final Color ring;

  const _SpotlightPainter({
    required this.hole,
    required this.dim,
    required this.ring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final window = hole;
    if (window == null) {
      canvas.drawPath(screen, Paint()..color = dim);
      return;
    }
    final rounded = RRect.fromRectAndRadius(window, const Radius.circular(20));
    // Even-odd fill leaves the window clear without a saveLayer.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(path, Paint()..color = dim);
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.dim != dim || old.ring != ring;
}

/// Swallows touches everywhere except inside [hole], where they reach the
/// app below.
class _Barrier extends SingleChildRenderObjectWidget {
  final Rect? hole;

  const _Barrier({required this.hole, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBarrier(hole);

  @override
  void updateRenderObject(BuildContext context, _RenderBarrier renderObject) {
    renderObject.hole = hole;
  }
}

class _RenderBarrier extends RenderProxyBox {
  _RenderBarrier(this.hole);

  Rect? hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (hole?.contains(position) ?? false) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// The tutorial's hint inside a sheet: shown while the current step is one
/// of [steps] and asks the user to try the sheet (in demo mode where the
/// step says so). Nothing while the tutorial is off.
class TutorialSheetHint extends StatelessWidget {
  /// Ids of the steps this sheet hosts.
  final Set<String> steps;

  /// Creates a [TutorialSheetHint].
  const TutorialSheetHint({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final controller = TutorialController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final step = controller.step;
        if (step == null || !steps.contains(step.id)) {
          return const SizedBox.shrink();
        }
        final palette = AppPalette.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: _style(
                          14.5,
                          FontWeight.w800,
                          palette.textPrimary,
                        ),
                      ),
                    ),
                    if (step.demo != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'تجربة',
                          style: _style(11, FontWeight.w800, palette.accent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  step.body,
                  style: _style(
                    12.5,
                    FontWeight.w500,
                    palette.textSecondary,
                  ).copyWith(height: 1.5),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: controller.requestSkip,
                    child: Text(
                      'تخطي الدليل',
                      style: _style(
                        12.5,
                        FontWeight.w600,
                        palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
