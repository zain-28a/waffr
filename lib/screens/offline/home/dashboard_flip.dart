// Home flip cards (part of dashboard.dart): a card that turns over about
// its horizontal axis to show another face, in the direction it was swiped.

part of 'dashboard.dart';

/// A card the user turns over with a vertical swipe. The card leans with
/// the finger; let go far enough (or flick) and [onTurn] is asked for the
/// next face, which the card turns over to. When there is no other face
/// ([canTurn] is false) the card makes a half turn, [onEmpty] runs at the
/// edge (to add one), and the card comes back.
///
/// A new [face] from anywhere else turns the card over too.
class _SwipeFlip extends StatefulWidget {
  /// Which face is on show; a new value turns the card over to [child].
  final Object face;

  /// True when a swipe has another face to turn to.
  final bool canTurn;

  /// Asks for another face: -1 for an upward swipe, 1 for a downward one.
  final FutureOr<void> Function(int direction) onTurn;

  /// Runs at the middle of a half turn, when there is no other face.
  final VoidCallback onEmpty;

  /// The face on show.
  final Widget child;

  const _SwipeFlip({
    required this.face,
    required this.canTurn,
    required this.onTurn,
    required this.onEmpty,
    required this.child,
  });

  @override
  State<_SwipeFlip> createState() => _SwipeFlipState();
}

class _SwipeFlipState extends State<_SwipeFlip>
    with SingleTickerProviderStateMixin {
  /// How far a drag may lean the card before it is let go, in quarter turns.
  static const double _maxLean = 0.42;

  /// The lean past which letting go turns the card over.
  static const double _commitLean = 0.2;

  /// The whole turn, from one face flat to the next face flat. It runs a
  /// touch past flat at the end and settles back.
  static const Curve _flipCurve = Cubic(0.45, 0, 0.2, 1.07);

  /// The card's turn about its horizontal axis, in quarter turns. A drag
  /// moves it directly: down is positive (the top edge comes forward), up
  /// is negative. During a flip it runs on to two quarter turns, the first
  /// showing the old face and the second the new one.
  late final AnimationController _turn = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onTurn);

  /// The face being turned away, while a flip runs.
  Widget? _outgoing;

  /// Which way the flip turns: 1 for a downward swipe, -1 for an upward one.
  int _direction = -1;

  /// The direction of a swipe still waiting for its new face.
  int? _asked;

  /// True once the flip has passed edge-on and shows the new face.
  bool _pastEdge = false;
  bool _dragging = false;

  /// A half turn (nothing to turn to) is running.
  bool _halfTurn = false;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SwipeFlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.face == widget.face) return;
    final direction = _asked ?? -1;
    _asked = null;
    _halfTurn = false;
    _dragging = false;
    if (AppMotion.reduced(context)) {
      _turn.stop();
      _turn.value = 0;
      _outgoing = null;
      return;
    }
    // The face on screen right now is the one that turns away.
    final shown = _outgoing != null && !_pastEdge
        ? _outgoing!
        : oldWidget.child;
    // A flip already under way starts over from the face it was showing.
    if (_outgoing != null) _turn.value = 0;
    final from = _turn.value * direction > 0 ? _turn.value : 0.0;
    _direction = direction;
    _outgoing = shown;
    _pastEdge = false;
    _turn.value = from;
    _turn
        .animateTo(
          2.0 * direction,
          duration: Duration(
            milliseconds: (560 * (1 - from.abs() / 2)).round(),
          ),
          curve: _flipCurve,
        )
        .whenComplete(() {
          if (!mounted || _turn.isAnimating) return;
          _turn.value = 0;
          setState(() => _outgoing = null);
        });
  }

  /// A tick as the card passes edge-on, where one face gives way to the
  /// other.
  void _onTurn() {
    if (_outgoing == null) return;
    final past = _turn.value.abs() >= 1;
    if (past == _pastEdge) return;
    _pastEdge = past;
    if (past) AppHaptics.tick();
    setState(() {});
  }

  void _dragStart(DragStartDetails details) {
    if (_outgoing != null || _halfTurn) return;
    _dragging = true;
    _turn.stop();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final height = context.size?.height ?? 200;
    final lean = _turn.value + details.delta.dy / height * 0.9;
    _turn.value = lean.clamp(-_maxLean, _maxLean);
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle();
  }

  void _dragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final lean = _turn.value;
    // A flick decides on its own; a slow drag has to lean far enough.
    final direction = velocity.abs() > 180
        ? velocity.sign.toInt()
        : (lean.abs() > _commitLean ? lean.sign.toInt() : 0);
    if (direction == 0) {
      _settle();
      return;
    }
    AppHaptics.selection();
    if (!widget.canTurn) {
      _turnHalf(direction);
      return;
    }
    if (AppMotion.reduced(context)) _settle();
    _asked = direction;
    final before = widget.face;
    Future.sync(() => widget.onTurn(direction)).whenComplete(() {
      if (!mounted) return;
      // Give the new face a frame to arrive; with nothing new, lie flat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _asked != direction || widget.face != before) return;
        _asked = null;
        if (_outgoing == null) _settle();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// Turns to edge-on, runs [_SwipeFlip.onEmpty] there, and comes back.
  void _turnHalf(int direction) {
    if (AppMotion.reduced(context)) {
      _turn.value = 0;
      widget.onEmpty();
      return;
    }
    _halfTurn = true;
    final from = _turn.value * direction > 0 ? _turn.value.abs() : 0.0;
    _turn.value = from * direction;
    _turn
        .animateTo(
          direction.toDouble(),
          duration: Duration(milliseconds: (240 * (1 - from)).round() + 40),
          curve: Curves.easeIn,
        )
        .whenComplete(() {
          if (!mounted || !_halfTurn) return;
          AppHaptics.tick();
          widget.onEmpty();
          _turn
              .animateTo(
                0,
                duration: const Duration(milliseconds: 340),
                curve: const Cubic(0.2, 0, 0.2, 1.12),
              )
              .whenComplete(() => _halfTurn = false);
        });
  }

  void _settle() {
    _turn.springTo(
      0,
      spring: AppSprings.spatial,
      reduced: AppMotion.reduced(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = _outgoing;
    final shown = outgoing != null && !_pastEdge ? outgoing : widget.child;

    // The vertical drag belongs to the card: it turns the card over
    // instead of scrolling the page.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _dragStart,
      onVerticalDragUpdate: _dragUpdate,
      onVerticalDragEnd: _dragEnd,
      onVerticalDragCancel: _dragCancel,
      child: AnimatedBuilder(
        animation: _turn,
        child: shown,
        builder: (context, child) {
          final turn = _turn.value;
          // Past edge-on the new face swings in from the other side.
          final quarter = outgoing != null && _pastEdge
              ? turn - 2 * _direction
              : turn;
          // The transform stays in the tree at rest too, so the face keeps
          // its state when a drag begins.
          return Transform(
            alignment: Alignment.center,
            transform: quarter == 0
                ? Matrix4.identity()
                : (Matrix4.identity()
                    ..setEntry(3, 2, 0.0008)
                    ..rotateX(quarter * math.pi / 2)),
            child: child,
          );
        },
      ),
    );
  }
}
