// Swipe a row sideways to reveal its actions (edit, delete). The row
// follows the finger, clicks once when the actions are fully out, and
// springs open or shut on release.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// One action behind a row.
@immutable
class SwipeAction {
  /// The action's icon.
  final IconData icon;

  /// Its name, read by screen readers and shown under the icon.
  final String label;

  /// Uses the destructive color (delete).
  final bool destructive;

  /// Called when the action is tapped; the row closes first.
  final VoidCallback onTap;

  /// An action.
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// Wraps [child] so a sideways swipe uncovers [actions] at its end edge.
/// Only one row is open at a time; opening another closes the first.
class SwipeActions extends StatefulWidget {
  /// The row.
  final Widget child;

  /// Actions uncovered by the swipe, in reading order.
  final List<SwipeAction> actions;

  /// False turns the swipe off (for example while selecting rows).
  final bool enabled;

  /// Creates a [SwipeActions].
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
  });

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  static const double _slot = 62;

  /// The row that is open now, so opening another can close it.
  static _SwipeActionsState? _open;

  /// How far the actions are uncovered, in pixels.
  late final AnimationController _reveal = AnimationController.unbounded(
    vsync: this,
  );

  bool _clicked = false;

  double get _max => _slot * widget.actions.length;

  @override
  void didUpdateWidget(covariant SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _reveal.value != 0) _settle(open: false);
  }

  @override
  void dispose() {
    if (identical(_open, this)) _open = null;
    _reveal.dispose();
    super.dispose();
  }

  void _settle({required bool open}) {
    if (open) {
      if (!identical(_open, this)) _open?._settle(open: false);
      _open = this;
    } else if (identical(_open, this)) {
      _open = null;
    }
    _reveal.springTo(
      open ? _max : 0,
      spring: AppSprings.spatial,
      reduced: AppMotion.reduced(context),
    );
  }

  void _onDrag(DragUpdateDetails details, bool rtl) {
    // The row moves toward the start edge; actions sit at the end edge.
    final delta = details.primaryDelta ?? 0;
    final next = (_reveal.value + (rtl ? delta : -delta)).clamp(
      0.0,
      _max * 1.15,
    );
    _reveal.value = next;
    final out = next >= _max * 0.98;
    if (out && !_clicked) AppHaptics.selection();
    _clicked = out;
  }

  void _onDragEnd(DragEndDetails details, bool rtl) {
    final velocity = (details.primaryVelocity ?? 0) * (rtl ? 1 : -1);
    _settle(
      open: velocity > 300 || (velocity > -300 && _reveal.value > _max * 0.45),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final palette = AppPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: widget.enabled
          ? (details) => _onDrag(details, rtl)
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (details) => _onDragEnd(details, rtl)
          : null,
      child: AnimatedBuilder(
        animation: _reveal,
        child: widget.child,
        builder: (context, child) {
          final shown = _reveal.value.clamp(0.0, _max * 1.15);
          return Stack(
            children: [
              if (shown > 0.5)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  width: shown,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.centerEnd,
                      minWidth: _max,
                      maxWidth: _max,
                      child: Row(
                        children: [
                          for (final action in widget.actions)
                            _ActionButton(
                              action: action,
                              width: _slot,
                              color: action.destructive
                                  ? AppColors.destructiveOf(context)
                                  : palette.accent,
                              onTap: () {
                                _settle(open: false);
                                action.onTap();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(rtl ? shown : -shown, 0),
                // While open, a tap on the row closes it.
                child: shown > 4
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _settle(open: false),
                        child: AbsorbPointer(child: child),
                      )
                    : child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A round tinted button with its label, behind the row.
class _ActionButton extends StatelessWidget {
  final SwipeAction action;
  final double width;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.action,
    required this.width,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: ExcludeSemantics(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(action.icon, size: 19, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontFamilyFallback: const ['Tajawal'],
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
