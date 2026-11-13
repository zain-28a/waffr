// Report chart (part of reportscreen.dart): the swipeable period card and
// its interactive area chart (drawn here, no chart package).

part of 'reportscreen.dart';

/// One PageView page: period label, older/newer arrows, and the area chart
/// (or empty state).
class _SpendingChartCard extends StatelessWidget {
  final _ReportData report;
  // Whether a newer period exists (false on the current period).
  final bool canShowNewer;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  const _SpendingChartCard({
    required this.report,
    required this.canShowNewer,
    required this.onOlder,
    required this.onNewer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final focus = report.focus;
    // Built once so the reveal animation below only moves the clip.
    final chart = RepaintBoundary(
      child: _SpendingAreaChart(
        buckets: report.chartBuckets,
        lastBucket: report.lastBucket,
        color: focus == null
            ? colors.accent
            : categoryChartColor(context, focus),
      ),
    );
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 13),
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: newer arrow, title and period label, older arrow.
          Row(
            children: [
              _PeriodArrow(
                icon: AppIcons.chevronForward,
                tooltip: 'الفترة الأحدث',
                enabled: canShowNewer,
                onTap: onNewer,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      focus == null ? 'الصرف خلال الفترة' : 'صرف $focus',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.fast),
                      child: Text(
                        report.period.label,
                        key: ValueKey((
                          report.period.range,
                          report.period.start,
                        )),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: const ['Tajawal'],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodArrow(
                icon: AppIcons.chevronBack,
                tooltip: 'الفترة السابقة',
                enabled: true,
                onTap: onOlder,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Chart body, or an empty state for a period with no expenses.
          Expanded(
            child: report.expenses.isEmpty
                ? const Center(
                    child: AppEmptyState(
                      icon: AppIcons.chartLine,
                      title: 'لا توجد مصروفات في هذه الفترة',
                      compact: true,
                    ),
                  )
                : Directionality(
                    textDirection: TextDirection.ltr,
                    // Each period's line draws itself in from the left.
                    // The chart is built once and only the clip moves, so
                    // the chart is not rebuilt (and re-tweened) every frame.
                    child: AnimatedRatio(
                      key: ValueKey((
                        report.period.range,
                        report.period.start,
                        focus,
                      )),
                      value: 1,
                      duration: const Duration(milliseconds: 900),
                      builder: (context, shown) =>
                          RevealClip(fraction: shown, child: chart),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Chevrons that step the period PageView older or newer.
class _PeriodArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _PeriodArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return IconButton(
      onPressed: enabled ? onTap : null,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: enabled
            ? colors.accent
            : colors.textSecondary.withValues(alpha: 0.35),
      ),
    );
  }
}

/// Spending over the period as a smooth area chart.
///
/// Only the buckets that have started are drawn, so a running period ends
/// at today instead of trailing off into empty days. Tap a point to read
/// it; press and hold, then drag, to scrub along the line with a haptic
/// tick per point. (A plain horizontal drag still pages between periods.)
class _SpendingAreaChart extends StatefulWidget {
  final List<_ChartBucket> buckets;

  /// Index of the last bucket to draw.
  final int lastBucket;

  /// Line and fill color: the accent, or the focused category's color.
  final Color color;

  const _SpendingAreaChart({
    required this.buckets,
    required this.lastBucket,
    required this.color,
  });

  @override
  State<_SpendingAreaChart> createState() => _SpendingAreaChartState();
}

class _SpendingAreaChartState extends State<_SpendingAreaChart> {
  /// Space kept for the axis labels around the plot.
  static const double _axisLeft = 40;
  static const double _axisBottom = 24;
  static const double _padTop = 34;
  static const double _padRight = 10;

  /// The point being read, or null.
  int? _selected;

  /// Hides the tooltip a few seconds after a tap.
  Timer? _hide;

  int get _count =>
      math.min(widget.lastBucket + 1, widget.buckets.length).clamp(1, 1 << 20);

  @override
  void didUpdateWidget(covariant _SpendingAreaChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.buckets, widget.buckets)) {
      _hide?.cancel();
      _selected = null;
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// The drawn point nearest to [x] (in widget coordinates).
  int _indexAt(double x, double width) {
    final plot = width - _axisLeft - _padRight;
    final count = _count;
    if (count <= 1 || plot <= 0) return 0;
    final step = plot / (count - 1);
    return ((x - _axisLeft) / step).round().clamp(0, count - 1);
  }

  void _select(double x, double width, {required bool sticky}) {
    final index = _indexAt(x, width);
    _hide?.cancel();
    if (!sticky) {
      _hide = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _selected = null);
      });
    }
    if (index == _selected) return;
    AppHaptics.selection();
    setState(() => _selected = index);
  }

  void _release() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final buckets = widget.buckets;
    final count = _count;

    // Scale: y rounded up to a whole number of nice intervals.
    var peak = 0.0;
    for (var i = 0; i < count; i++) {
      peak = math.max(peak, buckets[i].amount);
    }
    final maxValue = math.max(peak, 1).toDouble();
    final yInterval = _niceInterval(maxValue);
    final maxY = math
        .max(yInterval, (maxValue / yInterval).ceil() * yInterval)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final plot = Rect.fromLTRB(
          _axisLeft,
          _padTop,
          size.width - _padRight,
          size.height - _axisBottom,
        );
        final step = count > 1 ? plot.width / (count - 1) : 0.0;
        Offset pointAt(int i) => Offset(
          count > 1 ? plot.left + step * i : plot.center.dx,
          plot.bottom - (buckets[i].amount / maxY) * plot.height,
        );

        final selected = _selected != null && _selected! < count
            ? _selected
            : null;

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (recognizer) => recognizer.onTapUp = (details) => _select(
                    details.localPosition.dx,
                    size.width,
                    sticky: false,
                  ),
                ),
            // A short hold starts scrubbing, so the period pager keeps
            // plain horizontal drags.
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 180),
                  ),
                  (recognizer) {
                    void scrub(Offset at) =>
                        _select(at.dx, size.width, sticky: true);
                    recognizer.onLongPressStart = (details) {
                      scrub(details.localPosition);
                    };
                    recognizer.onLongPressMoveUpdate = (details) {
                      scrub(details.localPosition);
                    };
                    recognizer.onLongPressEnd = (_) => _release();
                    recognizer.onLongPressCancel = _release;
                  },
                ),
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _AreaChartPainter(
                    buckets: buckets,
                    count: count,
                    plot: plot,
                    maxY: maxY,
                    yInterval: yInterval,
                    selected: selected,
                    color: widget.color,
                    grid: colors.textPrimary.withValues(alpha: 0.07),
                    label: colors.textSecondary,
                    surface: colors.surface,
                  ),
                ),
              ),
              if (selected != null)
                _ChartTooltip(
                  anchor: pointAt(selected),
                  bounds: size,
                  title: buckets[selected].label,
                  value:
                      '${formatMoney(buckets[selected].amount)} $currencyLabel',
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the grid, axis labels, the filled area, the line, the "now" dot
/// and the scrub marker.
class _AreaChartPainter extends CustomPainter {
  final List<_ChartBucket> buckets;
  final int count;
  final Rect plot;
  final double maxY;
  final double yInterval;
  final int? selected;
  final Color color;
  final Color grid;
  final Color label;
  final Color surface;

  const _AreaChartPainter({
    required this.buckets,
    required this.count,
    required this.plot,
    required this.maxY,
    required this.yInterval,
    required this.selected,
    required this.color,
    required this.grid,
    required this.label,
    required this.surface,
  });

  Offset _point(int i) {
    final step = count > 1 ? plot.width / (count - 1) : 0.0;
    return Offset(
      count > 1 ? plot.left + step * i : plot.center.dx,
      plot.bottom - (buckets[i].amount / maxY) * plot.height,
    );
  }

  /// A smooth line through the points that never dips below a point or
  /// above one (monotone cubic), so it cannot swing under zero.
  Path _line(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length < 3) {
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }
    final n = points.length;
    final slopes = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      final dx = points[i + 1].dx - points[i].dx;
      slopes[i] = dx == 0 ? 0 : (points[i + 1].dy - points[i].dy) / dx;
    }
    final tangents = List<double>.filled(n, 0);
    tangents[0] = slopes[0];
    tangents[n - 1] = slopes[n - 2];
    for (var i = 1; i < n - 1; i++) {
      tangents[i] = slopes[i - 1] * slopes[i] <= 0
          ? 0
          : 2 * slopes[i - 1] * slopes[i] / (slopes[i - 1] + slopes[i]);
    }
    for (var i = 0; i < n - 1; i++) {
      final dx = (points[i + 1].dx - points[i].dx) / 3;
      path.cubicTo(
        points[i].dx + dx,
        points[i].dy + tangents[i] * dx,
        points[i + 1].dx - dx,
        points[i + 1].dy - tangents[i + 1] * dx,
        points[i + 1].dx,
        points[i + 1].dy,
      );
    }
    return path;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    required Alignment anchor,
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontFamilyFallback: const ['Tajawal'],
          fontSize: 10,
          fontWeight: weight,
          color: label,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    canvas.save();
    painter.paint(
      canvas,
      Offset(
        at.dx - painter.width * (anchor.x + 1) / 2,
        at.dy - painter.height * (anchor.y + 1) / 2,
      ),
    );
    canvas.restore();
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (plot.width <= 0 || plot.height <= 0 || count <= 0) return;

    // Horizontal grid lines with money labels on the left.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var value = 0.0; value <= maxY + 0.001; value += yInterval) {
      final y = plot.bottom - value / maxY * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        _axisMoney(value),
        Offset(plot.left - 8, y),
        anchor: Alignment.centerRight,
      );
    }

    // Bucket labels along the bottom.
    for (var i = 0; i < count; i++) {
      final text = buckets[i].axisLabel;
      if (text.isEmpty) continue;
      _text(
        canvas,
        text,
        Offset(_point(i).dx, plot.bottom + 8),
        anchor: i == 0 && count > 1
            ? Alignment.topLeft
            : (i == count - 1 && count > 1
                  ? Alignment.topRight
                  : Alignment.topCenter),
        weight: FontWeight.w700,
      );
    }

    final points = [for (var i = 0; i < count; i++) _point(i)];
    final line = _line(points);

    // Area: the color fading out toward the baseline.
    final area = Path.from(line)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0)],
        ).createShader(plot),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.4
        ..color = color,
    );

    // Where the line stands now.
    final last = points.last;
    canvas
      ..drawCircle(last, 7, Paint()..color = color.withValues(alpha: 0.2))
      ..drawCircle(last, 4, Paint()..color = surface)
      ..drawCircle(last, 2.6, Paint()..color = color);

    // Scrub marker: a guide line and a ringed dot on the point being read.
    final index = selected;
    if (index != null && index < count) {
      final at = points[index];
      canvas
        ..drawLine(
          Offset(at.dx, plot.top - 6),
          Offset(at.dx, plot.bottom),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 1,
        )
        ..drawCircle(at, 9, Paint()..color = color.withValues(alpha: 0.22))
        ..drawCircle(at, 5.5, Paint()..color = surface)
        ..drawCircle(at, 3.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter oldDelegate) =>
      !identical(oldDelegate.buckets, buckets) ||
      oldDelegate.count != count ||
      oldDelegate.plot != plot ||
      oldDelegate.maxY != maxY ||
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.label != label ||
      oldDelegate.surface != surface;
}

/// The glass label that floats over the point being read.
class _ChartTooltip extends StatelessWidget {
  /// The point it names, in the chart's coordinates.
  final Offset anchor;

  /// The chart's size; the label stays inside it.
  final Size bounds;
  final String title;
  final String value;

  const _ChartTooltip({
    required this.anchor,
    required this.bounds,
    required this.title,
    required this.value,
  });

  static const double _width = 124;
  static const double _height = 46;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final left = (anchor.dx - _width / 2).clamp(0.0, bounds.width - _width);
    // Above the point when there is room, otherwise below it.
    final above = anchor.dy - _height - 14;
    final top = above >= -30 ? above : anchor.dy + 14;

    return AnimatedPositioned(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.soft,
      left: left,
      top: top,
      width: _width,
      height: _height,
      child: IgnorePointer(
        child: LiquidGlass(
          radius: BorderRadius.circular(16),
          preset: GlassPreset.frosted.withOpacity(0.6),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontFamilyFallback: const ['Tajawal'],
                    fontSize: 11,
                    height: 1.2,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontFamilyFallback: const ['Tajawal'],
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Centered icon + message used when a chart or list has nothing to show.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppEmptyState(icon: icon, title: message),
    );
  }
}
