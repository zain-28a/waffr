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

/// The smart analysis beside the spending card: its mark, its name and
/// one line from it. Opens the full analysis, which grows out of the tile.
class _InsightTile extends StatelessWidget {
  /// The headline of the analysis; null before there is anything to read.
  final String? text;

  const _InsightTile({required this.text});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final line = text ?? 'ملاحظات واقتراحات عن مصاريفك';
    return Semantics(
      button: true,
      label: 'التحليل الذكي: $line',
      child: Pressable(
        onTap: () => openSmartAnalysis(context, InsightScope.reports),
        depth: 0.035,
        child: ExcludeSemantics(
          child: GlassContainer(
            colorType: GlassColorType.surface,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SmartSpark(size: 36),
                const SizedBox(height: 10),
                Text(
                  'التحليل الذكي',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: _text(
                    13.5,
                    weight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: AppMotion.of(context, AppMotion.medium),
                  child: Text(
                    line,
                    key: ValueKey(line),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _text(
                      11.5,
                      color: palette.textSecondary,
                    ).copyWith(height: 1.4),
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
