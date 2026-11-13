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

/// One line from the smart analysis; opens the full report.
class _InsightStrip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _InsightStrip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: 'التحليل الذكي: $text',
      child: Pressable(
        onTap: onTap,
        depth: 0.025,
        child: ExcludeSemantics(
          child: GlassContainer(
            colorType: GlassColorType.surface,
            borderRadius: 22,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    AppIcons.lightbulb,
                    size: 20,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.medium),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      text,
                      key: ValueKey(text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        13.5,
                        weight: FontWeight.w600,
                        color: palette.textPrimary,
                      ).copyWith(height: 1.45),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  AppIcons.chevronForward,
                  size: 18,
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
