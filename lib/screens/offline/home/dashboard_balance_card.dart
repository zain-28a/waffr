// Home balance card: available balance, cycle progress, currency dots
// and the add-income / add-expense actions.

part of 'dashboard.dart';

const double kBalanceCardActionTop = 14;

const double kBalanceCardActionEnd = 14;

const double kBalanceCardActionGap = 8;

// Current balance, remaining-ratio bar, and spend vs max. Vertical swipe
// cycles currency when more than one is enabled. Corner actions open income
// history and the shopping list.
class _BalanceCard extends StatelessWidget {
  final double balance;
  final double spent;
  final double maxBalance;
  final double ratio;
  final VoidCallback onShoppingList;
  final VoidCallback onIncomeLog;

  const _BalanceCard({
    required this.balance,
    required this.spent,
    required this.maxBalance,
    required this.ratio,
    required this.onShoppingList,
    required this.onIncomeLog,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final accent = palette.accent;
    final textSecondary = palette.textSecondary;

    final codes = CurrencyStore.instance.enabledCodes;
    final activeIndex = codes.indexOf(CurrencyStore.instance.activeCode);
    final showDots = codes.length > 1;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          GestureDetector(
            onVerticalDragUpdate: CurrencyStore.instance.enabledCodes.length > 1
                ? (_) {}
                : null,
            onVerticalDragEnd: CurrencyStore.instance.enabledCodes.length > 1
                ? (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -180) {
                      CurrencyStore.instance.selectNext();
                    } else if (velocity > 180) {
                      CurrencyStore.instance.selectPrevious();
                    }
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Padding(
                key: ValueKey(CurrencyStore.instance.activeCode),
                padding: EdgeInsetsDirectional.fromSTEB(
                  showDots ? 34 : 22,
                  20,
                  22,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'الرصيد الحالي',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: ['Tajawal'],
                            fontSize: 13.5,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: RollingMoney(
                              value: balance,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontFamilyFallback: ['Tajawal'],
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currencyLabel,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: ['Tajawal'],
                            fontSize: 15,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 0),
                    AnimatedRatio(
                      value: ratio,
                      builder: (context, shown) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${(shown * 100).round()}%',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontFamilyFallback: const ['Tajawal'],
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          _HorizontalProgress(
                            ratio: shown,
                            trackColor: accent.withValues(alpha: 0.12),
                            fillColor: accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'مصروف ${formatMoney(spent)} $currencyLabel '
                      'من ${formatMoney(maxBalance)} $currencyLabel',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: ['Tajawal'],
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showDots)
            PositionedDirectional(
              start: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CurrencyDots(
                  count: codes.length,
                  activeIndex: activeIndex < 0 ? 0 : activeIndex,
                  activeColor: accent,
                  inactiveColor: textSecondary.withValues(alpha: 0.35),
                ),
              ),
            ),
          PositionedDirectional(
            top: kBalanceCardActionTop,
            end: kBalanceCardActionEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassIconButton(
                  icon: Icons.payments_outlined,
                  label: 'سجل الدخل',
                  onPressed: onIncomeLog,
                ),
                const SizedBox(width: kBalanceCardActionGap),
                GlassIconButton(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'قائمة المشتريات',
                  onPressed: onShoppingList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Vertical page dots for the balance-card currency swipe. The active
// mark grows and takes the accent color; PositionedDirectional places
// the column on the start edge in both LTR and RTL.
class _CurrencyDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  final Color activeColor;
  final Color inactiveColor;

  const _CurrencyDots({
    required this.count,
    required this.activeIndex,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.enter,
              width: 6,
              height: index == activeIndex ? 18 : 6,
              decoration: BoxDecoration(
                color: index == activeIndex ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
      ],
    );
  }
}

class _HorizontalProgress extends StatelessWidget {
  final double ratio;
  final Color trackColor;
  final Color fillColor;

  const _HorizontalProgress({
    required this.ratio,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 30, color: trackColor),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(fillColor, Colors.white, 0.18)!,
                      fillColor,
                    ],
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

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final accent = palette.accent;
    final textPrimary = palette.textPrimary;

    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontFamilyFallback: ['Tajawal'],
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
