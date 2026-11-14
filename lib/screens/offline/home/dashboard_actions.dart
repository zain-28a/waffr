// Home quick actions and the one-line smart insight (part of
// dashboard.dart).

part of 'dashboard.dart';

/// The four things people do most from home, one tap each.
class _QuickActions extends StatelessWidget {
  final VoidCallback onExpense;
  final VoidCallback onIncome;
  final VoidCallback onSave;
  final VoidCallback onObligations;

  /// Obligations that wait for the user; shown as a dot on that action.
  final int attention;

  const _QuickActions({
    required this.onExpense,
    required this.onIncome,
    required this.onSave,
    required this.onObligations,
    required this.attention,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _QuickAction(
            label: 'مصروف',
            hint: 'إضافة مصروف',
            icon: AppIcons.arrowUpRight,
            primary: true,
            onTap: onExpense,
          ),
        ),
        Expanded(
          child: _QuickAction(
            label: 'دخل',
            hint: 'إضافة دخل',
            icon: AppIcons.arrowDownLeft,
            onTap: onIncome,
          ),
        ),
        Expanded(
          child: _QuickAction(
            label: 'توفير',
            hint: 'توفير مبلغ',
            icon: AppIcons.piggyBank,
            onTap: onSave,
          ),
        ),
        Expanded(
          child: _QuickAction(
            label: 'التزامات',
            hint: 'الالتزامات',
            icon: AppIcons.calendarRepeat,
            dot: attention > 0,
            onTap: onObligations,
          ),
        ),
      ],
    );
  }
}

/// A round button with its name under it. The primary one is filled with
/// the brand green; the others are quiet surface buttons.
class _QuickAction extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool primary;
  final bool dot;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.dot = false,
  });

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final face = primary
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // A gentle top-to-bottom shade of the one accent color.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(palette.accent, Colors.white, 0.14)!,
                  palette.accent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: isDark ? 0.36 : 0.38),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 25, color: palette.onAccent),
          )
        : GlassContainer(
            colorType: GlassColorType.surface,
            borderRadius: _size / 2,
            padding: EdgeInsets.zero,
            tintOpacity: 0.92,
            child: Center(child: Icon(icon, size: 24, color: palette.accent)),
          );

    return Semantics(
      button: true,
      label: hint,
      child: Pressable(
        onTap: onTap,
        depth: 0.07,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: _size,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    face,
                    if (dot)
                      PositionedDirectional(
                        top: 2,
                        end: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.warningOf(context),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(
                  12.5,
                  weight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into the smart analysis, above the spending card: a glass bar
/// with an edge in the smart colors, a line that invites the user in (it
/// changes every few seconds, and starts with the analysis's own headline
/// when there is one) and the analysis mark. Opens the full analysis, which
/// grows out of the bar.
class _InsightBar extends StatefulWidget {
  /// The headline of the analysis; null before there is anything to read.
  final String? insight;

  const _InsightBar({required this.insight});

  @override
  State<_InsightBar> createState() => _InsightBarState();
}

class _InsightBarState extends State<_InsightBar> {
  /// Invitations shown in turn after the headline.
  static const List<String> _invites = [
    'افتح التحليل الذكي لمصاريفك',
    'اكتشف أين يذهب مالك هذا الشهر',
    'اقتراحات لتوفّر أكثر من دخلك',
    'تعرّف على عاداتك في الصرف',
  ];

  /// How long each line stays.
  static const Duration _hold = Duration(milliseconds: 4200);

  Timer? _timer;
  int _index = 0;

  List<String> get _lines => [?widget.insight, ..._invites];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _InsightBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new headline is shown first.
    if (oldWidget.insight != widget.insight && widget.insight != null) {
      _index = 0;
    }
    _sync();
  }

  /// Turns the lines only while the tab is on screen.
  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && _timer == null) {
      _timer = Timer.periodic(_hold, (_) {
        if (mounted) setState(() => _index++);
      });
    } else if (!visible) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lines = _lines;
    final line = lines[_index % lines.length];
    final colors = smartGlowColors(context);
    const radius = BorderRadius.all(Radius.circular(24));

    return Semantics(
      button: true,
      label: 'التحليل الذكي',
      hint: line,
      child: Pressable(
        onTap: () => openSmartAnalysis(context, InsightScope.reports),
        depth: 0.03,
        child: ExcludeSemantics(
          child: DecoratedBox(
            // A faint glow in the smart colors around the bar.
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: colors[2].withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(-6, 4),
                ),
                BoxShadow(
                  color: colors[1].withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(6, 4),
                ),
              ],
            ),
            child: CustomPaint(
              foregroundPainter: _SmartEdgePainter(colors: colors, radius: 24),
              child: LiquidGlass(
                radius: radius,
                preset: GlassPreset.liquid,
                shadow: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 14, 14),
                  child: Row(
                    children: [
                      // The line on the start side (the right, in Arabic).
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AppMotion.of(context, AppMotion.slow),
                          switchInCurve: AppMotion.enter,
                          switchOutCurve: AppMotion.exit,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [...previous, ?current],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.35),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            line,
                            key: ValueKey(line),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              14.5,
                              weight: FontWeight.w600,
                              color: palette.textPrimary,
                            ).copyWith(height: 1.35),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // The analysis mark on the end side (the left).
                      const SmartSpark(size: 38),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's edge: a thin outline that runs through the smart colors.
class _SmartEdgePainter extends CustomPainter {
  final List<Color> colors;
  final double radius;

  const _SmartEdgePainter({required this.colors, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.8), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = SweepGradient(colors: [...colors, colors.first])
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SmartEdgePainter oldDelegate) =>
      oldDelegate.radius != radius || !listEquals(oldDelegate.colors, colors);
}
