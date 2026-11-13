// Shared bottom-sheet toolkit: open a glass sheet, lay out its body, and reuse
// the same field / chrome helpers so new sheets look and behave the same.
//
// The sheet is frosted liquid glass: the page stays visible, blurred, through
// it, and its top edge bends what is behind. The modal barrier is a light
// flat dim ([kSheetBarrierColor]); only the sheet's own area is blurred.
// On Android the sheet follows the back gesture before it is released.
//
// The field, amount, transition and button pieces live in the sheet_*.dart
// files next to this one and are re-exported here, so one import gives a
// sheet everything.

import 'dart:math' as math;

import 'package:waffr/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:waffr/widgets/glass/liquid_glass.dart';
import 'package:waffr/widgets/containers/amount_keypad.dart';
import 'package:waffr/widgets/containers/sheet_buttons.dart';
import 'package:waffr/widgets/motion/motion.dart';

export 'package:waffr/widgets/containers/amount_keypad.dart'
    show QuickAmounts, showQuickAmountsEditor;
export 'package:waffr/widgets/containers/sheet_amount_field.dart';
export 'package:waffr/widgets/containers/sheet_buttons.dart';
export 'package:waffr/widgets/containers/sheet_fields.dart';
export 'package:waffr/widgets/containers/sheet_transitions.dart';

/// Modal barrier tint. Dims the page behind the sheet without blurring it.
const Color kSheetBarrierColor = Color.fromARGB(92, 0, 0, 0);

/// How the sheet rises: fast at first, a gentle stop. The back gesture
/// inverts this curve to place the sheet under the finger.
const Curve _sheetCurve = Curves.easeOutCubic;

/// Top corners of every sheet.
const BorderRadius _sheetRadius = BorderRadius.vertical(
  top: Radius.circular(34),
);

/// The sheet's frosted glass. It hangs off the bottom of the screen, so
/// only its top edge and corners are optical.
class _SheetGlass extends StatelessWidget {
  final Widget child;

  const _SheetGlass({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlass(
      radius: _sheetRadius,
      bleed: const EdgeInsets.only(bottom: 96),
      preset: GlassPreset.frosted.withOpacity(isDark ? 0.8 : 0.78),
      shadow: false,
      light: const Alignment(-0.3, -1),
      child: child,
    );
  }
}

/// Opens a transparent modal bottom sheet wrapped in [_GlassSheetShell].
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: kSheetBarrierColor,
    elevation: 0,
    sheetAnimationStyle: AppMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 380),
            reverseDuration: Duration(milliseconds: 240),
            curve: _sheetCurve,
            reverseCurve: _sheetCurve,
          ),
    // The content is built once (inside a Builder child) so keyboard frames
    // only re-pad the sheet instead of rebuilding the whole form.
    builder: (context) => _SheetBackGesture(
      child: _GlassSheetShell(
        heightFactor: heightFactor,
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// Lets the sheet answer Android's predictive back gesture: while the
/// finger drags from the edge the sheet sinks with it, then either leaves
/// (released) or returns (cancelled). Button presses pop as usual.
class _SheetBackGesture extends StatefulWidget {
  final Widget child;

  const _SheetBackGesture({required this.child});

  @override
  State<_SheetBackGesture> createState() => _SheetBackGestureState();
}

class _SheetBackGestureState extends State<_SheetBackGesture>
    with WidgetsBindingObserver {
  /// How far the sheet sinks at the end of the drag, as a share of itself.
  static const double _sink = 0.28;

  ModalRoute<Object?>? _route;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = _route;
    if (route == null ||
        backEvent.isButtonEvent ||
        !route.isCurrent ||
        route.popDisposition != RoutePopDisposition.pop) {
      return false;
    }
    _dragging = true;
    route.handleStartBackGesture(progress: _valueFor(backEvent.progress));
    return true;
  }

  /// The route value that leaves the sheet sunk by `progress * _sink` of its
  /// height, undoing [_sheetCurve] (ease-out cubic).
  static double _valueFor(double progress) {
    final hidden = (progress.clamp(0.0, 1.0) * _sink).toDouble();
    return 1 - math.pow(hidden, 1 / 3).toDouble();
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_dragging) return;
    _route?.handleUpdateBackGestureProgress(
      progress: _valueFor(backEvent.progress),
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!_dragging) return;
    _dragging = false;
    _route?.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_dragging) return;
    _dragging = false;
    _route?.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Positions the sheet above the keyboard, optionally pins its height, and
/// docks the amount keypad under it at the bottom of the screen.
class _GlassSheetShell extends StatefulWidget {
  final Widget child;
  final double? heightFactor;

  const _GlassSheetShell({required this.child, this.heightFactor});

  @override
  State<_GlassSheetShell> createState() => _GlassSheetShellState();
}

class _GlassSheetShellState extends State<_GlassSheetShell> {
  /// The amount field that owns the keypad, if one is focused.
  final AmountKeypadController _keypad = AmountKeypadController();

  /// Keeps the sheet's state when the keypad opens and closes around it.
  final GlobalKey _sheetKey = GlobalKey();

  @override
  void dispose() {
    _keypad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = (screenHeight - keyboard - 28).clamp(
      220.0,
      screenHeight,
    );
    final heightFactor = widget.heightFactor;

    return AmountKeypadScope(
      controller: _keypad,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: ListenableBuilder(
            listenable: _keypad,
            builder: (context, _) {
              final binding = _keypad.binding;
              // Never both: the system keyboard wins while it is up.
              final docked = binding != null && keyboard == 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    // With the keypad docked the sheet no longer touches the
                    // bottom edge, so it gives up the bottom safe area.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: docked,
                      child: KeyedSubtree(
                        key: _sheetKey,
                        child: heightFactor == null
                            ? widget.child
                            : SizedBox(
                                height: (screenHeight * heightFactor).clamp(
                                  220.0,
                                  maxSheetHeight,
                                ),
                                child: widget.child,
                              ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: AppMotion.sizeOf(context, AppMotion.medium),
                    curve: AppMotion.enter,
                    alignment: Alignment.topCenter,
                    child: docked
                        ? _KeypadDock(binding: binding)
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The amount keypad as a panel along the bottom edge, where a keyboard
/// would be; the sheet rests on top of it.
class _KeypadDock extends StatelessWidget {
  final AmountKeypadBinding binding;

  const _KeypadDock({required this.binding});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.textPrimary.withValues(alpha: isDark ? 0.04 : 0.03),
          palette.surface,
        ),
        border: Border(
          top: BorderSide(color: palette.textSecondary.withValues(alpha: 0.14)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: AmountKeypad(binding: binding),
        ),
      ),
    );
  }
}

/// Fixed-height layout: pinned header, scrollable [body] below.
class GlassSheetFixedBody extends StatelessWidget {
  /// Pinned top part.
  final Widget header;

  /// Scrollable part under the header.
  final Widget body;

  /// Creates a [GlassSheetFixedBody].
  const GlassSheetFixedBody({
    super.key,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: _SheetGlass(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: header,
              ),
              const SizedBox(height: 8),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Default sheet shell: large top corners and a single scrollable column.
class GlassSheetBody extends StatelessWidget {
  /// Sheet content, top to bottom (entrances are staggered).
  final List<Widget> children;

  /// Space around the content.
  final EdgeInsetsGeometry padding;

  /// Creates a [GlassSheetBody].
  const GlassSheetBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    return _SheetGlass(
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: padding,
          child: AnimatedSize(
            duration: AppMotion.sizeOf(context, AppMotion.slow),
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: staggered(children, offset: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle, title, subtitle, close, and optional next control.
class GlassSheetHeader extends StatelessWidget {
  /// Sheet title.
  final String title;

  /// One line under the title.
  final String subtitle;

  /// Shows a "next" arrow that calls this; null hides it.
  final VoidCallback? onNext;

  /// Creates a [GlassSheetHeader].
  const GlassSheetHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final accent = palette.accent;
    final textSecondary = palette.textSecondary;

    return Column(
      children: [
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: textSecondary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 18),
        // Full width so the close / next buttons stay at the sheet edges even
        // when the title is short.
        SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: ['Tajawal'],
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: ['Tajawal'],
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                child: SheetCircleButton(
                  icon: AppIcons.close,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              if (onNext != null)
                Positioned(
                  right: 0,
                  child: SheetCircleButton(
                    icon: AppIcons.chevronForward,
                    onTap: onNext!,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
