// Home savings goal (part of dashboard.dart): one goal at a time on a card
// beside the recent expenses. A swipe turns the card over to the next goal;
// with no other goal it makes a half turn and starts a new one.

part of 'dashboard.dart';

/// The goal card. Shows [goals] one at a time, starting at [index]; a tap
/// opens the savings tab.
class _GoalTile extends StatelessWidget {
  final List<SavingsGoal> goals;
  final int index;
  final TransactionStore store;

  /// Shows the goal at this index.
  final ValueChanged<int> onIndex;
  final VoidCallback onOpen;
  final VoidCallback onCreate;

  const _GoalTile({
    required this.goals,
    required this.index,
    required this.store,
    required this.onIndex,
    required this.onOpen,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      return _SwipeFlip(
        face: 'none',
        canTurn: false,
        onTurn: (_) {},
        onEmpty: onCreate,
        child: _NewGoalCard(onTap: onCreate),
      );
    }
    final count = goals.length;
    final at = index % count;
    final goal = goals[at];
    return _SwipeFlip(
      face: goal.id,
      canTurn: count > 1,
      // Up is the next goal, down the previous one.
      onTurn: (direction) => onIndex((at + (direction < 0 ? 1 : -1)) % count),
      onEmpty: onCreate,
      child: KeyedSubtree(
        key: ValueKey(goal.id),
        child: _GoalFace(
          goal: goal,
          saved: store.currentSaved(goal),
          index: at,
          count: count,
          onTap: onOpen,
        ),
      ),
    );
  }
}

/// One goal: a vessel that fills as it is saved for, its name, and the
/// saved amount out of the target, with dots for the other goals.
class _GoalFace extends StatelessWidget {
  final SavingsGoal goal;
  final double saved;
  final int index;
  final int count;
  final VoidCallback onTap;

  const _GoalFace({
    required this.goal,
    required this.saved,
    required this.index,
    required this.count,
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
            colorType: GlassColorType.surface,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Column(
              children: [
                Text(
                  'هدف التوفير',
                  maxLines: 1,
                  style: _text(
                    11.5,
                    weight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                // The goal itself sits in the middle of whatever height the
                // card is given beside the recent expenses.
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      // The same vessel as on the savings tab: it fills as
                      // the goal is saved for.
                      LiquidVessel(
                        ratio: ratio,
                        size: 74,
                        radius: 22,
                        color: palette.accent,
                        track: palette.textPrimary.withValues(alpha: 0.07),
                        child: Text(
                          '${(ratio * 100).round()}%',
                          style: _text(
                            14.5,
                            weight: FontWeight.w700,
                            // Dark on an empty vessel, light once the liquid
                            // is behind it.
                            color: ratio > 0.5
                                ? palette.onAccent
                                : palette.textPrimary,
                            tabular: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        goal.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _text(
                          14,
                          weight: FontWeight.w700,
                          color: palette.textPrimary,
                        ).copyWith(height: 1.3),
                      ),
                      const SizedBox(height: 14),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatMoney(saved),
                          maxLines: 1,
                          style: _text(
                            17,
                            weight: FontWeight.w700,
                            color: palette.accent,
                            tabular: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'من ${formatMoney(target)} $symbol',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          11,
                          color: palette.textSecondary,
                          tabular: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
                if (count > 1) ...[
                  const SizedBox(height: 10),
                  _PageDots(count: count, index: index),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of small dots: which of [count] goals is on show.
class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Many goals would not fit; the dots stop at seven.
    final shown = math.min(count, 7);
    final active = index * shown ~/ count;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var dot = 0; dot < shown; dot++)
          AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.enter,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: dot == active ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: dot == active
                  ? palette.accent
                  : palette.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

/// Dashed "new goal" card, while there is no goal yet.
class _NewGoalCard extends StatelessWidget {
  final VoidCallback onTap;

  const _NewGoalCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const label = 'أنشئ هدفك الأول';

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
              radius: 28,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(AppIcons.add, size: 22, color: palette.accent),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: _text(
                      13,
                      weight: FontWeight.w700,
                      color: palette.textPrimary,
                    ).copyWith(height: 1.35),
                  ),
                ],
              ),
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
