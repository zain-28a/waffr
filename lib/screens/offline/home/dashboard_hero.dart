// Home balance hero (part of dashboard.dart): the balance on a dimensional
// card. The card leans toward a finger and with the phone's motion, its
// lights shift with the lean, and it turns over in the direction of the
// swipe when the currency changes.

part of 'dashboard.dart';

/// Current balance, how much of the period's money is left, and spend vs
/// max. A vertical swipe cycles currency when more than one is enabled: the
/// card leans with the finger and turns over the way it was swiped. Corner
/// chips open the income history and the shopping list.
class _BalanceHero extends StatefulWidget {
  // Values for the active currency, taken from TransactionStore.
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  // Corner chip callbacks.
  final VoidCallback onShoppingList;
  final void Function(BuildContext origin) onIncomeLog;

  const _BalanceHero({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
    required this.onShoppingList,
    required this.onIncomeLog,
  });

  @override
  State<_BalanceHero> createState() => _BalanceHeroState();
}

class _BalanceHeroState extends State<_BalanceHero>
    with SingleTickerProviderStateMixin {
  /// Mint used for the bar and highlights on the dark card surface.
  static const Color _mint = Color(0xFF9FD8A6);

  /// How far a drag may lean the card before it is let go, in quarter turns.
  static const double _maxLean = 0.42;

  /// The lean past which letting go turns the card over.
  static const double _commitLean = 0.2;

  /// The whole turn, from one face flat to the next face flat. It runs a
  /// touch past flat at the end and settles back.
  static const Curve _flipCurve = Cubic(0.45, 0, 0.2, 1.07);

  final CurrencyStore _currencies = CurrencyStore.instance;

  /// The card's turn about its horizontal axis, in quarter turns. A drag
  /// moves it directly: down is positive (the top edge comes forward), up
  /// is negative. During a flip it runs on to two quarter turns, the first
  /// showing the old face and the second the new one.
  late final AnimationController _turn = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onTurn);

  /// The currency on the card's face.
  late String _code = _currencies.activeCode;

  /// The face being turned away, while a flip runs.
  Widget? _outgoing;

  /// The face as last built, kept so it can be the outgoing one.
  Widget? _lastFace;

  /// Which way the flip turns: 1 for a downward swipe, -1 for an upward one.
  int _direction = -1;

  /// True once the flip has passed edge-on and shows the new face.
  bool _pastEdge = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _currencies.addListener(_onCurrency);
  }

  @override
  void dispose() {
    _currencies.removeListener(_onCurrency);
    _turn.dispose();
    super.dispose();
  }

  /// A new active currency: turn the card over to it, the way the swipe
  /// that asked for it was going.
  void _onCurrency() {
    final active = _currencies.activeCode;
    if (!mounted || active == _code) return;
    _code = active;
    final last = _lastFace;
    if (last == null || AppMotion.reduced(context)) {
      _turn.stop();
      _turn.value = 0;
      setState(() => _outgoing = null);
      return;
    }
    // A flip already under way starts over from the face it was showing.
    if (_outgoing != null) _turn.value = 0;
    final from = _turn.value * _direction > 0 ? _turn.value : 0.0;
    final target = 2.0 * _direction;
    setState(() {
      _outgoing = last;
      _pastEdge = false;
      _dragging = false;
    });
    _turn.value = from;
    _turn
        .animateTo(
          target,
          duration: Duration(
            milliseconds: (640 * (1 - from.abs() / 2)).round(),
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
    if (_outgoing != null) return;
    _dragging = true;
    _turn.stop();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final height = context.size?.height ?? 200;
    final lean = _turn.value + details.delta.dy / height * 0.9;
    _turn.value = lean.clamp(-_maxLean, _maxLean);
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
    if (direction == 0 || AppMotion.reduced(context)) {
      _settle();
      if (direction == 0) return;
    }
    _direction = direction;
    AppHaptics.selection();
    final change = direction < 0
        ? _currencies.selectNext()
        : _currencies.selectPrevious();
    final before = _code;
    change.whenComplete(() {
      // Nothing to turn to after all: lay the card flat again.
      if (mounted && _code == before && _outgoing == null) _settle();
    });
  }

  void _settle() {
    _turn.springTo(
      0,
      spring: AppSprings.spatial,
      reduced: AppMotion.reduced(context),
    );
  }

  Widget _face(List<String> codes, String active) {
    final index = codes.indexOf(active);
    // Everything on one face belongs to one currency.
    return KeyedSubtree(
      key: ValueKey(active),
      child: _HeroFace(
        balance: widget.balance,
        spent: widget.spent,
        maxBalance: widget.maxBalance,
        ratio: widget.ratio,
        symbol: currencyLabel,
        dots: codes.length > 1 ? codes.length : 0,
        activeDot: index < 0 ? 0 : index,
        mint: _mint,
        onShoppingList: widget.onShoppingList,
        onIncomeLog: widget.onIncomeLog,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codes = _currencies.enabledCodes;
    final many = codes.length > 1;
    final face = _face(codes, _currencies.activeCode);
    // Until the store's change reaches this state, the face on show is
    // still the old currency's; only that one may become the outgoing face.
    if (_currencies.activeCode == _code) _lastFace = face;

    final outgoing = _outgoing;
    final shown = outgoing != null && !_pastEdge ? outgoing : face;

    return RepaintBoundary(
      // The vertical drag belongs to the card: it turns the card over
      // instead of scrolling the page.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: many ? _dragStart : null,
        onVerticalDragUpdate: many ? _dragUpdate : null,
        onVerticalDragEnd: many ? _dragEnd : null,
        onVerticalDragCancel: many
            ? () {
                if (!_dragging) return;
                _dragging = false;
                _settle();
              }
            : null,
        child: AnimatedBuilder(
          animation: _turn,
          child: shown,
          builder: (context, child) {
            final turn = _turn.value;
            // Past edge-on the new face swings in from the other side.
            final quarter = outgoing != null && _pastEdge
                ? turn - 2 * _direction
                : turn;
            // The transform stays in the tree at rest too, so the face
            // keeps its state when a drag begins.
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
      ),
    );
  }
}

/// One side of the card: the surface, its light, and one currency's balance
/// with a large bar for what is left of the period. The card leans toward
/// a finger and with the phone's motion.
class _HeroFace extends StatelessWidget {
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  final String symbol;

  /// Number of currency dots; 0 hides them.
  final int dots;
  final int activeDot;
  final Color mint;
  final VoidCallback onShoppingList;
  final void Function(BuildContext origin) onIncomeLog;

  const _HeroFace({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
    required this.symbol,
    required this.dots,
    required this.activeDot,
    required this.mint,
    required this.onShoppingList,
    required this.onIncomeLog,
  });

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.onHero;
    final soft = ink.withValues(alpha: 0.74);

    final content = Stack(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            dots > 0 ? 36 : 24,
            22,
            24,
            22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leaves room for the corner chips on the same line.
              SizedBox(
                height: 40,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('الرصيد الحالي', style: _text(14, color: soft)),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: RollingMoney(
                        value: balance,
                        style: _text(
                          48,
                          weight: FontWeight.w700,
                          color: ink,
                          tabular: true,
                        ).copyWith(height: 1.05, letterSpacing: -0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(symbol, style: _text(16, color: soft)),
                ],
              ),
              const SizedBox(height: 16),
              // How much of the period's money is left: the share in large
              // figures over a thick bar.
              AnimatedRatio(
                value: ratio,
                builder: (context, shown) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            'المتبقي من رصيد الفترة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(13, color: soft),
                          ),
                        ),
                        Text(
                          '${(shown * 100).round()}%',
                          style: _text(
                            20,
                            weight: FontWeight.w700,
                            color: ink,
                            tabular: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _HeroBar(ratio: shown, color: mint),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'مصروف ${formatMoney(spent)} '
                'من ${formatMoney(maxBalance)} $symbol',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(
                  13,
                  weight: FontWeight.w500,
                  color: ink.withValues(alpha: 0.86),
                  tabular: true,
                ),
              ),
            ],
          ),
        ),
        // Currency page dots on the start edge.
        if (dots > 0)
          PositionedDirectional(
            start: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CurrencyDots(
                count: dots,
                activeIndex: activeDot,
                activeColor: ink,
                inactiveColor: ink.withValues(alpha: 0.3),
              ),
            ),
          ),
        // Corner chips: income log and shopping list.
        PositionedDirectional(
          top: 22,
          end: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeroChip(
                icon: AppIcons.banknote,
                label: 'سجل الدخل',
                onPressed: onIncomeLog,
              ),
              const SizedBox(width: 8),
              _HeroChip(
                icon: AppIcons.list,
                label: 'قائمة المشتريات',
                onPressed: (_) => onShoppingList(),
              ),
            ],
          ),
        ),
      ],
    );

    const radius = BorderRadius.all(Radius.circular(30));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The lean turns the whole card: its shadow, its rounded edge and its
    // lights move as one object, so no edge is left behind.
    return TiltBuilder(
      child: content,
      builder: (context, tilt, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..rotateX(-tilt.dy * 0.075)
          ..rotateY(tilt.dx * 0.075),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: AppColors.heroEnd.withValues(alpha: isDark ? 0.6 : 0.4),
                blurRadius: 34,
                spreadRadius: -6,
                // The shadow falls a little away from the raised side.
                offset: Offset(-tilt.dx * 5, 18 - tilt.dy * 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: CustomPaint(
              painter: _HeroSurfacePainter(tilt: tilt),
              foregroundPainter: _HeroLightPainter(tilt: tilt),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The thick bar under the balance: how much of the period's money is left.
/// It fills from the start edge, so in Arabic it grows from the right.
class _HeroBar extends StatelessWidget {
  final double ratio;
  final Color color;

  const _HeroBar({required this.ratio, required this.color});

  static const double _height = 18;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_height / 2),
      child: SizedBox(
        height: _height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.16)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_height / 2),
                  // Lit from above, like the card it sits on.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.white, 0.22)!, color],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card body: deep green with a soft white light in one corner, a
/// cooler one in the opposite corner, and the wallet's stitching. The
/// lights slide a little against the lean, which reads as depth.
class _HeroSurfacePainter extends CustomPainter {
  final Offset tilt;

  const _HeroSurfacePainter({required this.tilt});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.heroStart,
            AppColors.heroMiddle,
            AppColors.heroEnd,
          ],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );

    void light(Offset at, double radius, Color color, double alpha) {
      final center = Offset(at.dx * size.width, at.dy * size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    light(
      Offset(0.86 - tilt.dx * 0.12, 0.02 - tilt.dy * 0.12),
      size.width * 0.72,
      Colors.white,
      0.18,
    );
    light(
      Offset(0.08 - tilt.dx * 0.1, 1.0 - tilt.dy * 0.1),
      size.width * 0.6,
      AppColors.darkGlow,
      0.24,
    );

    // Stitching, as on the wallet in the logo.
    final stitch = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(9), const Radius.circular(22)),
      );
    final thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.14);
    for (final metric in stitch.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 17) {
        canvas.drawPath(metric.extractPath(at, at + 9), thread);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeroSurfacePainter oldDelegate) =>
      oldDelegate.tilt != tilt;
}

/// Light on the card's edge: a rim that is bright toward the light and a
/// shade at the far edge.
class _HeroLightPainter extends CustomPainter {
  final Offset tilt;

  const _HeroLightPainter({required this.tilt});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      const Radius.circular(30),
    );

    // Thickness: shade gathering at the bottom edge.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.14),
          ],
          stops: const [0.72, 1],
        ).createShader(rect),
    );

    // Rim: follows the light, never a uniform border.
    final light = Alignment(-0.7 - tilt.dx * 0.6, -1 - tilt.dy * 0.4);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: light,
          end: Alignment(-light.x, -light.y),
          colors: [
            Colors.white.withValues(alpha: 0.62),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.02),
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.3),
          ],
          stops: const [0, 0.3, 0.5, 0.72, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroLightPainter oldDelegate) =>
      oldDelegate.tilt != tilt;
}

/// Small translucent button in the hero's corner.
class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Called with the chip's own context, so a page can open out of it.
  final void Function(BuildContext chip) onPressed;

  const _HeroChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: () => onPressed(context),
        depth: 0.08,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 20, color: AppColors.onHero),
        ),
      ),
    );
  }
}

/// Vertical page dots for the hero's currency swipe. The active mark grows
/// and brightens; PositionedDirectional places the column on the start
/// edge in both LTR and RTL.
class _CurrencyDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final Color activeColor;
  final Color inactiveColor;

  const _CurrencyDots({
    required this.count,
    required this.activeIndex,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.enter,
              width: 6,
              height: index == activeIndex ? 18 : 6,
              decoration: BoxDecoration(
                color: index == activeIndex ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
      ],
    );
  }
}
