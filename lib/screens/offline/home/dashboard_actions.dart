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

/// The way into the smart analysis, above the spending card: a card like
/// the others with a lightbulb and one line of what the analysis found.
/// The line turns every few seconds through several wordings of the
/// headline and the titles of the findings. Opens the full analysis, which
/// grows out of the card.
class _InsightBar extends StatefulWidget {
  /// Headline wordings and finding titles: null before the first read,
  /// empty with nothing logged yet.
  final List<String>? lines;

  const _InsightBar({required this.lines});

  @override
  State<_InsightBar> createState() => _InsightBarState();
}

class _InsightBarState extends State<_InsightBar> {
  /// Shown while nothing is logged yet.
  static const List<String> _starters = [
    'لنبدأ معاً: سجّل مصاريفك لأحلّلها لك.',
    'التحليل جاهز حالما تبدأ بالتسجيل.',
    'سجّل أول مصروف لتظهر لك أول ملاحظة.',
    'كل مصروف تسجّله يجعل التحليل أدق.',
    'بانتظار مصاريفك لأبدأ التحليل.',
  ];

  /// How long each line stays.
  static const Duration _hold = Duration(milliseconds: 4200);

  Timer? _timer;
  int _index = 0;

  /// Shown for the moment before the analysis is first read.
  static const List<String> _reading = ['إليك أهم ما لاحظته في صرفك.'];

  List<String> get _lines {
    final lines = widget.lines;
    if (lines == null) return _reading;
    return lines.isEmpty ? _starters : lines;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _InsightBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new reading starts from its first wording.
    if (!listEquals(oldWidget.lines, widget.lines)) _index = 0;
    _sync();
  }

  /// Turns the lines only while the tab is on screen.
  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && _timer == null) {
      _timer = Timer.periodic(_hold, (_) {
        if (mounted && _lines.length > 1) setState(() => _index++);
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

    return Semantics(
      button: true,
      label: 'التحليل الذكي: $line',
      child: Pressable(
        onTap: () => openSmartAnalysis(context, InsightScope.reports),
        depth: 0.025,
        child: ExcludeSemantics(
          child: GlassContainer(
            colorType: GlassColorType.surface,
            borderRadius: 24,
            padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 12, 12),
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
                    transitionBuilder: (child, animation) => FadeTransition(
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
                        14,
                        weight: FontWeight.w600,
                        color: palette.textPrimary,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // The lightbulb on the end side (the left).
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    AppIcons.lightbulb,
                    size: 21,
                    color: palette.accent,
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
