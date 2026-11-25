// Home spending card (part of dashboard.dart): where the money went in the
// chosen period (week, month, balance period or all time), as a donut whose
// middle shows the largest category's icon and share, with the categories
// listed beside it, across the full width of the screen.

part of 'dashboard.dart';

/// Category shares of the chosen period's spending. Opens the reports tab.
class _SpendingCard extends StatelessWidget {
  final SpendingBreakdown breakdown;

  /// The period shown, and a callback to switch it.
  final SpendingPeriod period;
  final ValueChanged<SpendingPeriod> onPeriod;

  /// True when some expense exists in another period, so an empty period
  /// reads "nothing in this period" rather than "log your first expense".
  final bool hasHistory;

  final VoidCallback onTap;

  const _SpendingCard({
    required this.breakdown,
    required this.period,
    required this.onPeriod,
    required this.hasHistory,
    required this.onTap,
  });

  /// Categories named beside the donut; the donut shows them all.
  static const int _listed = 5;

  @override
  Widget build(BuildContext context) {
    final top = breakdown.top;

    return _SectionCard(
      title: 'توزيع المصروفات',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHistory) ...[
            _PeriodChips(selected: period, onSelected: onPeriod),
            const SizedBox(height: 10),
          ],
          if (top == null)
            _EmptyState(
              icon: AppIcons.chartPie,
              message: hasHistory
                  ? 'لا مصروفات مسجّلة في هذه المدة'
                  : 'ستظهر النسب بعد تسجيل أول مصروف',
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Row(
                children: [
                  // On the start side (the right, in Arabic): the largest
                  // categories, one under another; the first is the one in
                  // the middle of the donut.
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in breakdown.items.take(_listed))
                          _Share(
                            color: categoryChartColor(context, item.category),
                            name: item.category,
                            percent: (item.share * 100).round(),
                            highlighted: identical(item, top),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  _Donut(breakdown: breakdown),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The period switch at the top of the spending card: four equal segments.
/// Taps here change the period without opening the reports tab.
class _PeriodChips extends StatelessWidget {
  final SpendingPeriod selected;
  final ValueChanged<SpendingPeriod> onSelected;

  const _PeriodChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final track = palette.textSecondary.withValues(alpha: 0.09);
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final period in SpendingPeriod.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: period == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (period == selected) return;
                    AppHaptics.selection();
                    onSelected(period);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.of(context, AppMotion.fast),
                    curve: AppMotion.enter,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: period == selected
                          ? palette.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: period == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        period.label,
                        maxLines: 1,
                        style: _text(
                          12.5,
                          weight: period == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: period == selected
                              ? palette.textPrimary
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One legend line: color dot, category name and its share.
class _Share extends StatelessWidget {
  final Color color;
  final String name;
  final int percent;

  /// The largest category, shown in the donut's middle: its name is bold.
  final bool highlighted;

  const _Share({
    required this.color,
    required this.name,
    required this.percent,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
              style: _text(
                13,
                weight: highlighted ? FontWeight.w700 : FontWeight.w400,
                color: highlighted
                    ? palette.textPrimary
                    : palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '\u2066$percent%\u2069',
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
/// slice is a little thicker, and the middle shows that category's icon in
/// its color with its share of the period.
class _Donut extends StatefulWidget {
  final SpendingBreakdown breakdown;

  const _Donut({required this.breakdown});

  /// Outer size, with room for the thicker slice.
  static const double size = 120;

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
  late Map<String, double> _to = _shares(widget.breakdown);

  static Map<String, double> _shares(SpendingBreakdown breakdown) => {
    for (final item in breakdown.items) item.category: item.share,
  };

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
    final next = _shares(widget.breakdown);
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
    final top = widget.breakdown.top!;
    final topColor = categoryChartColor(context, top.category);
    final percent = (top.share * 100).round();

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
                for (final item in widget.breakdown.items) item.category,
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
                        bold: category == top.category,
                      ),
                  ],
                  sweep: AppMotion.enter.transform(_sweep.value),
                ),
              );
            },
          ),
          // The largest category: its icon on a tint of its color, and its
          // share of the period under it.
          Semantics(
            label: 'أكبر تصنيف ${top.category} بنسبة $percent%',
            excludeSemantics: true,
            child: SizedBox(
              width: 66,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: topColor.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      categoryFor(top.category).icon,
                      size: 18,
                      color: topColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '\u2066$percent%\u2069',
                      maxLines: 1,
                      style: _text(
                        16,
                        weight: FontWeight.w700,
                        color: palette.textPrimary,
                        tabular: true,
                      ),
                    ),
                  ),
                ],
              ),
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
  static const double _thin = 15;
  static const double _thick = 20;

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
