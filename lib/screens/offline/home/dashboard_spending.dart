// Home spending card (part of dashboard.dart): where the money went, as a
// donut with the total in its middle and the categories listed beside it.

part of 'dashboard.dart';

/// Category shares of this period's spending. Opens the reports tab.
class _SpendingCard extends StatelessWidget {
  // Per-category totals, largest first.
  final List<({String category, double amount})> totals;
  final double totalExpense;
  final VoidCallback onTap;

  const _SpendingCard({
    required this.totals,
    required this.totalExpense,
    required this.onTap,
  });

  /// Categories named beside the donut; the donut shows them all.
  static const int _listed = 4;

  @override
  Widget build(BuildContext context) {
    final has = totalExpense > 0 && totals.isNotEmpty;

    return _SectionCard(
      title: 'توزيع المصروفات',
      compact: true,
      onTap: onTap,
      child: !has
          ? const _EmptyState(
              icon: AppIcons.chartPie,
              message: 'ستظهر النسب بعد تسجيل أول مصروف',
              compact: true,
            )
          : Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Row(
                children: [
                  // On the start side (the right, in Arabic): the largest
                  // categories, one under another.
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in totals.take(_listed))
                          _Share(
                            color: categoryChartColor(context, item.category),
                            name: item.category,
                            percent: (item.amount / totalExpense * 100).round(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Donut(totals: totals, total: totalExpense),
                ],
              ),
            ),
    );
  }
}

/// One legend line: color dot, category name and its share.
class _Share extends StatelessWidget {
  final Color color;
  final String name;
  final int percent;

  const _Share({
    required this.color,
    required this.name,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(12.5, color: palette.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$percent%',
            style: _text(
              13,
              weight: FontWeight.w700,
              color: palette.textPrimary,
              tabular: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// The spending donut. It draws itself in once; after that, a change in
/// the numbers glides each slice to its new size. The largest category's
/// slice is a little thicker. The middle holds the period's total.
class _Donut extends StatefulWidget {
  final List<({String category, double amount})> totals;
  final double total;

  const _Donut({required this.totals, required this.total});

  /// Outer size, with room for the thicker slice.
  static const double size = 94;

  @override
  State<_Donut> createState() => _DonutState();
}

class _DonutState extends State<_Donut> with TickerProviderStateMixin {
  /// The first sweep around the ring.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: AppMotion.countUp,
  );

  /// From the old shares to the new ones, after a change.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
    value: 1,
  );

  /// Each category's share of the ring before and after the change.
  Map<String, double> _from = const {};
  late Map<String, double> _to = _shares(widget.totals);

  static Map<String, double> _shares(
    List<({String category, double amount})> totals,
  ) {
    final sum = totals.fold<double>(0, (total, item) => total + item.amount);
    if (sum <= 0) return const {};
    return {for (final item in totals) item.category: item.amount / sum};
  }

  @override
  void initState() {
    super.initState();
    _sweep.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _sweep.value = 1;
      _glide.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _Donut oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _shares(widget.totals);
    if (mapEquals(next, _to)) return;
    _from = _current();
    _to = next;
    if (AppMotion.reduced(context)) {
      _glide.value = 1;
    } else {
      _glide.forward(from: 0);
    }
  }

  /// The shares as drawn right now.
  Map<String, double> _current() {
    final t = AppMotion.enter.transform(_glide.value);
    return {
      for (final category in {..._from.keys, ..._to.keys})
        category: lerpDouble(_from[category] ?? 0, _to[category] ?? 0, t)!,
    };
  }

  @override
  void dispose() {
    _sweep.dispose();
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final largest = widget.totals.first.category;

    return SizedBox.square(
      dimension: _Donut.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_sweep, _glide]),
            builder: (context, _) {
              final shares = _current();
              // Largest first, as the list beside it; slices that are
              // leaving shrink away at the end.
              final order = [
                for (final item in widget.totals) item.category,
                for (final category in shares.keys)
                  if (!_to.containsKey(category)) category,
              ];
              return CustomPaint(
                size: const Size.square(_Donut.size),
                painter: _DonutPainter(
                  slices: [
                    for (final category in order)
                      (
                        share: shares[category] ?? 0,
                        color: categoryChartColor(context, category),
                        bold: category == largest,
                      ),
                  ],
                  sweep: AppMotion.enter.transform(_sweep.value),
                ),
              );
            },
          ),
          // The total in the middle, rolling to its new value.
          SizedBox(
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RollingMoney(
                    value: widget.total,
                    style: _text(
                      14,
                      weight: FontWeight.w700,
                      color: palette.textPrimary,
                      tabular: true,
                    ),
                  ),
                ),
                Text(
                  currencyLabel,
                  maxLines: 1,
                  style: _text(10, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the donut's slices clockwise from the top, with a thin gap
/// between them once the first sweep is done.
class _DonutPainter extends CustomPainter {
  final List<({double share, Color color, bool bold})> slices;

  /// How much of the ring is drawn yet (0..1).
  final double sweep;

  const _DonutPainter({required this.slices, required this.sweep});

  /// Ring thickness; the largest slice reaches a little further out.
  static const double _thin = 12;
  static const double _thick = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Slices share the inner edge, so the thick one only grows outward.
    final inner = size.shortestSide / 2 - _thick;
    final gap = slices.where((slice) => slice.share > 0.001).length > 1
        ? 0.035 * sweep
        : 0.0;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final angle = slice.share * math.pi * 2 * sweep;
      if (angle <= 0.0005) continue;
      final width = slice.bold ? _thick : _thin;
      final radius = inner + width / 2;
      final drawn = math.max(0.0, angle - gap);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start + (angle - drawn) / 2,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = slice.color,
      );
      start += angle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.sweep != sweep || !listEquals(oldDelegate.slices, slices);
}
