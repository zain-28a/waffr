// Home savings goals (part of dashboard.dart): a swipeable row of goal
// cards, each with a progress ring, ending with a "new goal" card.

part of 'dashboard.dart';

/// Active goals side by side. A goal opens the savings tab; the last card
/// starts a new goal.
class _GoalsCarousel extends StatelessWidget {
  final List<SavingsGoal> goals;
  final TransactionStore store;
  final VoidCallback onOpen;
  final VoidCallback onCreate;

  const _GoalsCarousel({
    required this.goals,
    required this.store,
    required this.onOpen,
    required this.onCreate,
  });

  static const double _height = 148;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'أهداف التوفير',
                  style: _text(
                    16.5,
                    weight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (goals.isNotEmpty) _HeaderLink(label: 'الكل', onTap: onOpen),
            ],
          ),
        ),
        if (goals.isEmpty)
          _NewGoalCard(wide: true, onTap: onCreate)
        else
          SizedBox(
            height: _height,
            // Swallow the row's scroll so the shell's tab pager stays put.
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) => true,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: goals.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: kCardGap),
                itemBuilder: (context, index) {
                  if (index == goals.length) {
                    return _NewGoalCard(onTap: onCreate);
                  }
                  final goal = goals[index];
                  return _GoalCard(
                    goal: goal,
                    saved: store.currentSaved(goal),
                    onTap: onOpen,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// One goal: its ring, name, and saved amount out of the target.
class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final double saved;
  final VoidCallback onTap;

  const _GoalCard({
    required this.goal,
    required this.saved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final target = goal.targetAmount;
    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    final symbol = currencyLabelFor(goal.currencyCode);

    return Semantics(
      button: true,
      label:
          '${goal.name}: ${formatMoney(saved)} من ${formatMoney(target)} $symbol',
      child: Pressable(
        onTap: onTap,
        depth: 0.035,
        child: ExcludeSemantics(
          child: GlassContainer(
            width: 208,
            colorType: GlassColorType.surface,
            borderRadius: 26,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedRatio(
                      value: ratio,
                      builder: (context, shown) => SizedBox.square(
                        dimension: 50,
                        child: CustomPaint(
                          painter: _RingPainter(
                            ratio: shown,
                            track: palette.accent.withValues(alpha: 0.12),
                            color: palette.accent,
                            stroke: 5,
                          ),
                          child: Center(
                            child: Text(
                              '${(shown * 100).round()}%',
                              style: _text(
                                11.5,
                                weight: FontWeight.w700,
                                color: palette.textPrimary,
                                tabular: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        goal.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          14.5,
                          weight: FontWeight.w700,
                          color: palette.textPrimary,
                        ).copyWith(height: 1.3),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatMoney(saved),
                        style: _text(
                          19,
                          weight: FontWeight.w700,
                          color: palette.accent,
                          tabular: true,
                        ),
                      ),
                      TextSpan(
                        text: ' / ${formatMoney(target)} $symbol',
                        style: _text(
                          12,
                          color: palette.textSecondary,
                          tabular: true,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed "new goal" card at the end of the row; [wide] fills the row when
/// there is no goal yet.
class _NewGoalCard extends StatelessWidget {
  final bool wide;
  final VoidCallback onTap;

  const _NewGoalCard({required this.onTap, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final label = wide ? 'أنشئ هدفك الأول' : 'هدف جديد';

    final body = Flex(
      direction: wide ? Axis.horizontal : Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(AppIcons.add, size: 22, color: palette.accent),
        ),
        SizedBox(width: wide ? 12 : 0, height: wide ? 0 : 10),
        Text(
          label,
          style: _text(
            13.5,
            weight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        depth: 0.035,
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: palette.accent.withValues(alpha: 0.35),
              radius: 26,
            ),
            child: SizedBox(
              width: wide ? double.infinity : 124,
              height: wide ? 84 : null,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stitched outline, like the seam on the wallet in the logo.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 15) {
        canvas.drawPath(metric.extractPath(at, at + 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Progress ring: a faint full track and a solid arc from the top.
class _RingPainter extends CustomPainter {
  final double ratio;
  final Color track;
  final Color color;
  final double stroke;

  const _RingPainter({
    required this.ratio,
    required this.track,
    required this.color,
    this.stroke = 5.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    final sweep = math.pi * 2 * ratio.clamp(0.0, 1.0);
    if (sweep <= 0.01) return;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.track != track ||
      oldDelegate.color != color;
}
