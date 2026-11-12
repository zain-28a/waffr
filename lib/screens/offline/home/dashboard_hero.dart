// Home balance hero (part of dashboard.dart): the balance on a dimensional
// glass card. The card leans toward a finger and with the phone's motion,
// its light and inner glow shift with the lean, and the wallet's current
// smile is pressed faintly into its surface.

part of 'dashboard.dart';

/// Current balance, how much of the period's money is left, and spend vs
/// max. A vertical swipe cycles currency when more than one is enabled.
/// Corner chips open the income history and the shopping list.
class _BalanceHero extends StatelessWidget {
  // Values for the active currency, taken from TransactionStore.
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  // Corner chip callbacks.
  final VoidCallback onShoppingList;
  final VoidCallback onIncomeLog;

  const _BalanceHero({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
    required this.onShoppingList,
    required this.onIncomeLog,
  });

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(30));

  /// Mint used for the ring and highlights on the dark card surface.
  static const Color _mint = Color(0xFF9FD8A6);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencies = CurrencyStore.instance;
    final codes = currencies.enabledCodes;
    final activeIndex = codes.indexOf(currencies.activeCode);
    final many = codes.length > 1;
    const ink = AppColors.onHero;
    final soft = ink.withValues(alpha: 0.72);

    final content = Stack(
      children: [
        // An empty drag-update handler claims the vertical gesture so the
        // swipe switches currency instead of scrolling the page.
        GestureDetector(
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
          // Content slides in when the active currency changes.
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(currencies.activeCode),
              padding: EdgeInsetsDirectional.fromSTEB(
                many ? 36 : 24,
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
                      child: Text(
                        'الرصيد الحالي',
                        style: _text(14, color: soft),
                      ),
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
                      Text(currencyLabel, style: _text(16, color: soft)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // How much of the period's money is left, as a ring.
                  Row(
                    children: [
                      AnimatedRatio(
                        value: ratio,
                        builder: (context, shown) => SizedBox.square(
                          dimension: 54,
                          child: CustomPaint(
                            painter: _RingPainter(
                              ratio: shown,
                              track: ink.withValues(alpha: 0.16),
                              start: _mint,
                              end: AppColors.darkGlow,
                            ),
                            child: Center(
                              child: Text(
                                '${(shown * 100).round()}%',
                                style: _text(
                                  12.5,
                                  weight: FontWeight.w700,
                                  color: ink,
                                  tabular: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المتبقي من رصيد الفترة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(12.5, color: soft),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'مصروف ${formatMoney(spent)} '
                              'من ${formatMoney(maxBalance)} $currencyLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(
                                13.5,
                                weight: FontWeight.w600,
                                color: ink.withValues(alpha: 0.94),
                                tabular: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Currency page dots on the start edge.
        if (many)
          PositionedDirectional(
            start: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CurrencyDots(
                count: codes.length,
                activeIndex: activeIndex < 0 ? 0 : activeIndex,
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

    // The smile pressed into the card follows the wallet's mood.
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: WalletMood.instance,
        builder: (context, child) {
          final mouth = MouthShape.of(
            WalletMood.instance.form ?? SmileForm.excellent,
          );
          return TiltBuilder(
            child: child,
            builder: (context, tilt, child) => Transform(
              alignment: Alignment.center,
              // A slight perspective lean: the pressed side sinks away.
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateX(-tilt.dy * 0.075)
                ..rotateY(tilt.dx * 0.075),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.heroEnd.withValues(
                        alpha: isDark ? 0.55 : 0.34,
                      ),
                      blurRadius: 30,
                      spreadRadius: -6,
                      offset: Offset(-tilt.dx * 10, 18 - tilt.dy * 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: _radius,
                  child: CustomPaint(
                    painter: _HeroSurfacePainter(tilt: tilt, mouth: mouth),
                    foregroundPainter: _HeroLightPainter(tilt: tilt),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        child: content,
      ),
    );
  }
}

/// The card body: deep green glass with a teal and a mint glow inside it,
/// the wallet's stitching, and its smile as a faint watermark. The glows
/// and the smile slide a little against the lean, which reads as depth.
class _HeroSurfacePainter extends CustomPainter {
  final Offset tilt;
  final MouthShape mouth;

  const _HeroSurfacePainter({required this.tilt, required this.mouth});

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
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );

    void glow(Offset at, double radius, Color color, double alpha) {
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

    glow(
      Offset(0.9 - tilt.dx * 0.12, 0.05 - tilt.dy * 0.12),
      size.width * 0.7,
      AppColors.darkGlow,
      0.34,
    );
    glow(
      Offset(0.05 - tilt.dx * 0.1, 1.05 - tilt.dy * 0.1),
      size.width * 0.6,
      const Color(0xFF7BC47F),
      0.26,
    );

    // The smile: the logo's mouth, large and faint, toward the left.
    final mark = size.height * 1.15;
    canvas
      ..save()
      ..translate(
        size.width * 0.23 - MouthShape.centerX * mark - tilt.dx * 6,
        size.height * 0.56 - mouth.cornerY * mark - tilt.dy * 4,
      )
      ..drawPath(
        mouth.toPath(mark),
        Paint()..color = Colors.white.withValues(alpha: 0.075),
      )
      ..restore();

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
      oldDelegate.tilt != tilt || oldDelegate.mouth != mouth;
}

/// Light on the card's glass: a soft sweep that travels with the lean, a
/// rim that is bright toward the light, and a shade at the far edge.
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

    // Sweep: a diagonal band of light sliding across with the lean.
    final slide = tilt.dx * 0.9 - tilt.dy * 0.3;
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1.4 + slide, -1),
          end: Alignment(0.6 + slide, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.11),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.36, 0.5, 0.64],
        ).createShader(rect),
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
            Colors.black.withValues(alpha: 0.2),
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

/// Progress ring: a faint full track and a gradient arc from the top.
class _RingPainter extends CustomPainter {
  final double ratio;
  final Color track;
  final Color start;
  final Color end;
  final double stroke;

  const _RingPainter({
    required this.ratio,
    required this.track,
    required this.start,
    required this.end,
    this.stroke = 5.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    final sweep = math.pi * 2 * ratio.clamp(0.0, 1.0);
    if (sweep <= 0.01) return;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 2)
      ..translate(-size.width / 2, -size.height / 2)
      ..drawArc(
        rect,
        0,
        sweep,
        false,
        base
          ..shader = SweepGradient(
            colors: [start, end, start],
            stops: const [0, 0.7, 1],
          ).createShader(rect),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.track != track ||
      oldDelegate.start != start ||
      oldDelegate.end != end;
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
