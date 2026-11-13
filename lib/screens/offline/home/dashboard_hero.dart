// Home balance hero (part of dashboard.dart): the balance on a dimensional
// card. The card leans toward a finger and with the phone's motion, its
// lights shift with the lean, and it flips over when the currency changes.

part of 'dashboard.dart';

/// Current balance, how much of the period's money is left, and spend vs
/// max. A vertical swipe cycles currency when more than one is enabled, and
/// the whole card flips over to the next currency. Corner chips open the
/// income history and the shopping list.
class _BalanceHero extends StatefulWidget {
  // Values for the active currency, taken from TransactionStore.
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  // Corner chip callbacks.
  final VoidCallback onShoppingList;
  final VoidCallback onIncomeLog;

  const _BalanceHero({
    super.key,
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

class _BalanceHeroState extends State<_BalanceHero> {
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(30));

  /// Mint used for the bar and highlights on the dark card surface.
  static const Color _mint = Color(0xFF9FD8A6);

  /// The currency on the card's face, and which way the last flip turned.
  String _code = CurrencyStore.instance.activeCode;
  bool _forward = true;

  /// Notes a currency change so the flip turns the way the list moved.
  void _trackCurrency(List<String> codes, String active) {
    if (active == _code) return;
    final from = codes.indexOf(_code);
    final to = codes.indexOf(active);
    final count = codes.length;
    _forward = from < 0 || to < 0 || count < 2
        ? true
        : (to - from + count) % count <= count / 2;
    _code = active;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencies = CurrencyStore.instance;
    final codes = currencies.enabledCodes;
    final active = currencies.activeCode;
    final activeIndex = codes.indexOf(active);
    final many = codes.length > 1;
    _trackCurrency(codes, active);

    // One face of the card: everything on it belongs to one currency.
    final face = KeyedSubtree(
      key: ValueKey(active),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.heroEnd.withValues(alpha: isDark ? 0.6 : 0.4),
              blurRadius: 34,
              spreadRadius: -6,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: _HeroFace(
            balance: widget.balance,
            spent: widget.spent,
            maxBalance: widget.maxBalance,
            ratio: widget.ratio,
            symbol: currencyLabel,
            dots: many ? codes.length : 0,
            activeDot: activeIndex < 0 ? 0 : activeIndex,
            mint: _mint,
            onShoppingList: widget.onShoppingList,
            onIncomeLog: widget.onIncomeLog,
          ),
        ),
      ),
    );

    return RepaintBoundary(
      // An empty drag-update handler claims the vertical gesture so the
      // swipe switches currency instead of scrolling the page.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: many ? (_) {} : null,
        onVerticalDragEnd: many
            ? (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -180) {
                  AppHaptics.selection();
                  currencies.selectNext();
                } else if (velocity > 180) {
                  AppHaptics.selection();
                  currencies.selectPrevious();
                }
              }
            : null,
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, const Duration(milliseconds: 560)),
          switchInCurve: Curves.linear,
          switchOutCurve: Curves.linear,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) => _CardFlip(
            animation: animation,
            incoming: child.key == ValueKey(active),
            forward: _forward,
            child: child,
          ),
          child: face,
        ),
      ),
    );
  }
}

/// Turns the whole card over its horizontal axis. The outgoing face swings
/// away during the first half, the incoming one swings in during the
/// second, so the card reads as one object with two sides.
class _CardFlip extends StatelessWidget {
  final Animation<double> animation;

  /// True for the face arriving, false for the one leaving.
  final bool incoming;

  /// Which way the card turns.
  final bool forward;
  final Widget child;

  const _CardFlip({
    required this.animation,
    required this.incoming,
    required this.forward,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // The switcher runs 0..1 for the incoming face and 1..0 for the
        // outgoing one; each face owns half of that range.
        final t = animation.value;
        final visible = incoming ? t >= 0.5 : t > 0.5;
        if (!visible) return Visibility.maintain(visible: false, child: child!);
        final half = AppMotion.standard.transform(
          ((1 - t) * 2).clamp(0.0, 1.0),
        );
        final turn = (incoming == forward ? -1 : 1) * half * math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0008)
            ..rotateX(turn),
          child: child,
        );
      },
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
  final VoidCallback onIncomeLog;

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
                onPressed: onShoppingList,
              ),
            ],
          ),
        ),
      ],
    );

    return TiltBuilder(
      child: content,
      builder: (context, tilt, child) => Transform(
        alignment: Alignment.center,
        // A slight perspective lean: the pressed side sinks away.
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..rotateX(-tilt.dy * 0.075)
          ..rotateY(tilt.dx * 0.075),
        child: CustomPaint(
          painter: _HeroSurfacePainter(tilt: tilt),
          foregroundPainter: _HeroLightPainter(tilt: tilt),
          child: child,
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
  final VoidCallback onPressed;

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
        onTap: onPressed,
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
