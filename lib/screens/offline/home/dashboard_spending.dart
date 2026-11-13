// Home spending strip (part of dashboard.dart): where the money went, as
// one stacked bar and the three largest categories.

part of 'dashboard.dart';

/// Category shares of this period's spending. Opens the reports tab.
class _SpendingStrip extends StatelessWidget {
  final List<({String category, double amount})> totals;
  final double totalExpense;
  final VoidCallback onTap;

  const _SpendingStrip({
    required this.totals,
    required this.totalExpense,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final has = totalExpense > 0 && totals.isNotEmpty;

    return _SectionCard(
      title: 'توزيع المصروفات',
      trailing: has ? formatMoney(totalExpense) : null,
      trailingCaption: has ? currencyLabel : null,
      onTap: onTap,
      child: !has
          ? const _EmptyState(
              icon: AppIcons.chartPie,
              message: 'ستظهر النسب بعد تسجيل أول مصروف',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Segments grow in from the start edge.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: AppMotion.of(context, AppMotion.countUp),
                  curve: AppMotion.enter,
                  builder: (context, shown, child) =>
                      RevealClip(fraction: shown, child: child!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, item) in totals.indexed) ...[
                            if (index > 0) const SizedBox(width: 2),
                            Expanded(
                              flex: math.max(
                                1,
                                (item.amount / totalExpense * 1000).round(),
                              ),
                              child: ColoredBox(
                                color: categoryChartColor(
                                  context,
                                  item.category,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final (index, item) in totals.take(3).indexed) ...[
                      if (index > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _Share(
                          color: categoryChartColor(context, item.category),
                          name: item.category,
                          percent: (item.amount / totalExpense * 100).round(),
                          textPrimary: palette.textPrimary,
                          textSecondary: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// One legend entry: color dot, share and category name.
class _Share extends StatelessWidget {
  final Color color;
  final String name;
  final int percent;
  final Color textPrimary;
  final Color textSecondary;

  const _Share({
    required this.color,
    required this.name,
    required this.percent,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$percent% ',
                  style: _text(
                    13,
                    weight: FontWeight.w700,
                    color: textPrimary,
                    tabular: true,
                  ),
                ),
                TextSpan(
                  text: name,
                  style: _text(12.5, color: textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
