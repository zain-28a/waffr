// Savings hub: period net-saved card, total balance, active goals, and entry
// points that open create / manual save / withdraw / shopping / recurring sheets.

import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/motion/active_listenable_builder.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/savings/sheets/completed_goals_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/manage_goals_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/manual_save_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/periodic_goals_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/withdraw_savings_sheet.dart';
import 'package:waffr/widgets/button/glass_button.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/containers/pinned_period_scroll_view.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/widgets/smart/smart_analysis_button.dart';

// Range chips + swipeable period card, total savings, goal progress, and sheet launches.
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPeriodOffset = 240;

  final TransactionStore _store = TransactionStore.instance;
  final PageController _periodController = PageController();

  SavingsRange _range = SavingsRange.month;
  int _periodOffset = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded().then((_) => _store.processDuePeriods());
  }

  @override
  void dispose() {
    _periodController.dispose();
    super.dispose();
  }

  // New range jumps the period pager back to the current window.
  void _selectRange(SavingsRange range) {
    if (_range == range) return;

    setState(() {
      _range = range;
      _periodOffset = 0;
    });

    if (_periodController.hasClients) {
      _periodController.jumpToPage(0);
    }
  }

  void _showOlderPeriod() {
    if (_periodOffset >= _maxPeriodOffset - 1) return;

    _periodController.nextPage(
      duration: AppMotion.medium,
      curve: Curves.easeOutCubic,
    );
  }

  void _showNewerPeriod() {
    if (_periodOffset == 0) return;

    _periodController.previousPage(
      duration: AppMotion.medium,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ActiveListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final goals = _store.activeGoals;

        return PinnedPeriodScrollView(
          key: const PageStorageKey('savings-period-scroll'),
          options: [for (final range in SavingsRange.values) range.label],
          selected: _range.label,
          onSelected: (label) {
            _selectRange(
              SavingsRange.values.firstWhere((range) => range.label == label),
            );
          },
          child: Column(
            children: staggered([
              SizedBox(
                height: 108,
                child: PageView.builder(
                  controller: _periodController,
                  itemCount: _maxPeriodOffset,
                  clipBehavior: Clip.none,
                  onPageChanged: (index) {
                    setState(() => _periodOffset = index);
                  },
                  itemBuilder: (context, offset) {
                    final pagePeriod = CalendarPeriod.forRange(_range, offset);

                    final previousPeriod = CalendarPeriod.forRange(
                      _range,
                      offset + 1,
                    );

                    return _PeriodSavingsCard(
                      range: _range,
                      period: pagePeriod,
                      amount: _store.savingsNetDuring(
                        pagePeriod.start,
                        pagePeriod.end,
                      ),
                      previousAmount: _store.savingsNetDuring(
                        previousPeriod.start,
                        previousPeriod.end,
                      ),
                      isCurrent: offset == 0,
                      canShowNewer: offset > 0,
                      onOlder: _showOlderPeriod,
                      onNewer: _showNewerPeriod,
                    );
                  },
                ),
              ),

              const SizedBox(height: kCardGap),

              _PlanButtonsRow(
                periodicLabel: _store.hasActivePeriodicPlan
                    ? 'خطة جارية'
                    : 'خطط التوفير',
                periodicActive: _store.hasActivePeriodicPlan,
                onPeriodic: () => showPeriodicGoalsSheet(context),
                onCompleted: () => showCompletedGoalsSheet(context),
              ),

              const SizedBox(height: kCardGap),

              _ActiveGoalsPanel(
                goals: goals,
                store: _store,
                onManage: () => showManageGoalsSheet(context),
                onCreate: () => showCreateGoalSheet(context),
              ),

              const SizedBox(height: kCardGap),

              _SplitActionRow(
                leading: _TotalSavingsCard(total: _store.savingsBalance),
                first: _ActionButton(
                  label: 'توفير مبلغ',
                  onTap: () => showManualSaveSheet(context),
                ),
                second: _ActionButton(
                  label: 'سحب إلى الرصيد',
                  onTap: () => showWithdrawSavingsSheet(context),
                ),
              ),

              const SizedBox(height: kCardGap),

              const ShoppingListPreviewCard(),

              const SizedBox(height: 12),
            ]),
          ),
        );
      },
    );
  }
}

// One PageView page: net saved in that window vs the previous period.
class _PeriodSavingsCard extends StatelessWidget {
  final SavingsRange range;
  final CalendarPeriod period;
  final double amount;
  final double previousAmount;
  final bool isCurrent;
  final bool canShowNewer;
  final VoidCallback onOlder;
  final VoidCallback onNewer;

  const _PeriodSavingsCard({
    required this.range,
    required this.period,
    required this.amount,
    required this.previousAmount,
    required this.isCurrent,
    required this.canShowNewer,
    required this.onOlder,
    required this.onNewer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    final comparison = _SavingsComparison.calculate(
      current: amount,
      previous: previousAmount,
      colors: colors,
    );

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PeriodArrow(
                icon: Icons.chevron_right_rounded,
                tooltip: 'الفترة الأحدث',
                enabled: canShowNewer,
                onTap: onNewer,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'المبلغ الموفَّر',
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.fast),
                      child: Text(
                        isCurrent
                            ? CalendarPeriod.currentPeriodCaption(range)
                            : CalendarPeriod.rangeLabel(range, period),
                        key: ValueKey(period.start),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodArrow(
                icon: Icons.chevron_left_rounded,
                tooltip: 'الفترة السابقة',
                enabled: true,
                onTap: onOlder,
              ),
            ],
          ),

          const SizedBox(height: 2),

          if (amount <= 0)
            Text(
              'لا يوجد توفير في هذه الفترة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                fontSize: 13,
                color: colors.textPrimary.withValues(alpha: 0.55),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RollingMoney(
                      value: amount,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  currencyLabel,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                if (comparison != null) ...[
                  const SizedBox(width: 8),
                  Icon(comparison.icon, size: 15, color: comparison.color),
                  const SizedBox(width: 2),
                  Text(
                    comparison.text,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: comparison.color,
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

// Percent delta badge when the previous period had savings to compare against.
class _SavingsComparison {
  final IconData icon;
  final Color color;
  final String text;

  const _SavingsComparison({
    required this.icon,
    required this.color,
    required this.text,
  });

  static _SavingsComparison? calculate({
    required double current,
    required double previous,
    required AppPalette colors,
  }) {
    if (previous <= 0) return null;

    final percentage = (current - previous) / previous * 100;

    if (percentage == 0) return null;

    final isPositive = percentage > 0;

    return _SavingsComparison(
      icon: isPositive
          ? Icons.trending_up_rounded
          : Icons.trending_down_rounded,
      color: isPositive ? colors.accent : colors.textPrimary,
      text:
          '${isPositive ? '+' : '−'}'
          '${percentage.abs().toStringAsFixed(0)}%',
    );
  }
}

// Chevrons that step the savings period PageView.
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
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        icon,
        color: enabled
            ? colors.accent
            : colors.textSecondary.withValues(alpha: 0.35),
      ),
    );
  }
}

// Total savings card, the smart analysis tile, and the manual-save and
// withdraw buttons in one row.
class _SplitActionRow extends StatelessWidget {
  final Widget leading;
  final Widget first;
  final Widget second;

  const _SplitActionRow({
    required this.leading,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: leading),

          const SizedBox(width: kCardGap),

          const SizedBox(
            width: 88,
            child: SmartAnalysisButton(
              scope: InsightScope.savings,
              style: SmartButtonStyle.tile,
            ),
          ),

          const SizedBox(width: kCardGap),

          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(child: first),
                const SizedBox(height: kCardGap),
                Expanded(child: second),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Active goals (or empty create CTA). Collapsed it shows the first goal; a
// tap opens the rest in place, about two and a half goals tall with the
// remainder scrolling. The arrow under the list folds it back.
class _ActiveGoalsPanel extends StatefulWidget {
  final List<SavingsGoal> goals;
  final TransactionStore store;
  final VoidCallback onManage;
  final VoidCallback onCreate;

  const _ActiveGoalsPanel({
    required this.goals,
    required this.store,
    required this.onManage,
    required this.onCreate,
  });

  @override
  State<_ActiveGoalsPanel> createState() => _ActiveGoalsPanelState();
}

class _ActiveGoalsPanelState extends State<_ActiveGoalsPanel> {
  // Height of one goal row plus the gap after it, before text scaling.
  static const double _goalExtent = 78;
  static const double _goalGap = 14;

  bool _expanded = false;

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    AppHaptics.selection();
    setState(() => _expanded = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    final ordered = List<SavingsGoal>.from(widget.goals)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    if (ordered.isEmpty) {
      return GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 28,
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SavingsGoalsHeader(
              colors: colors,
              count: 0,
              onManage: widget.onManage,
            ),
            const SizedBox(height: 14),
            const AppEmptyState(
              icon: Icons.flag_outlined,
              title: 'لا توجد أهداف حالياً',
              compact: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: _CreateGoalCard(onCreate: widget.onCreate),
            ),
          ],
        ),
      );
    }

    final canExpand = ordered.length > 1;
    final expanded = _expanded && canExpand;

    Widget goalRow(int i) => _GoalProgressCard(
          goal: ordered[i],
          saved: widget.store.currentSaved(ordered[i]),
        );

    final Widget goalsBody;
    if (!expanded) {
      goalsBody = goalRow(0);
    } else {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final maxHeight =
          (2.5 * (_goalExtent * scale + _goalGap)).clamp(0.0, double.infinity);
      final list = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(height: _goalGap),
            goalRow(i),
          ],
        ],
      );
      goalsBody = ordered.length > 2
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(child: list),
            )
          : list;
    }

    return GestureDetector(
      onTap: canExpand
          ? (expanded ? null : () => _setExpanded(true))
          : widget.onManage,
      behavior: HitTestBehavior.opaque,
      child: GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 28,
        padding: EdgeInsets.fromLTRB(16, 15, 16, canExpand ? 4 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SavingsGoalsHeader(
              colors: colors,
              count: ordered.length,
              onManage: widget.onManage,
            ),
            const SizedBox(height: 14),
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: goalsBody,
            ),
            if (canExpand)
              _ExpandToggle(
                expanded: expanded,
                totalCount: ordered.length,
                onTap: () => _setExpanded(!expanded),
              ),
          ],
        ),
      ),
    );
  }
}

// Arrow under the goals list: opens the rest, or folds them back.
class _ExpandToggle extends StatelessWidget {
  final bool expanded;
  final int totalCount;
  final VoidCallback onTap;

  const _ExpandToggle({
    required this.expanded,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      button: true,
      label: expanded ? 'إخفاء باقي الأهداف' : 'عرض باقي الأهداف',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.fast),
                child: expanded
                    ? const SizedBox.shrink()
                    : Text(
                        'عرض كل الأهداف (\u2066$totalCount\u2069)',
                        key: ValueKey(totalCount),
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: const ['Tajawal'],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: AppMotion.of(context, AppMotion.medium),
                curve: AppMotion.standard,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Title row for the goals panel.
class _SavingsGoalsHeader extends StatelessWidget {
  final AppPalette colors;
  final int count;
  final VoidCallback onManage;

  const _SavingsGoalsHeader({
    required this.colors,
    required this.count,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.wallet_rounded,
            size: 19,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أهداف التوفير',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (count > 0) ...[
          const SizedBox(width: 2),
          IconButton(
            onPressed: onManage,
            tooltip: 'إدارة الأهداف',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.tune_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// Opens the periodic plan sheet and the completed-goals sheet.
class _PlanButtonsRow extends StatelessWidget {
  final String periodicLabel;
  final bool periodicActive;
  final VoidCallback onPeriodic;
  final VoidCallback onCompleted;

  const _PlanButtonsRow({
    required this.periodicLabel,
    required this.periodicActive,
    required this.onPeriodic,
    required this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: periodicLabel,
              onTap: onPeriodic,
              leading: periodicActive
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppPalette.of(context).accent,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: kCardGap),
          Expanded(
            child: _ActionButton(
              label: 'الأهداف المحققة',
              onTap: onCompleted,
            ),
          ),
        ],
      ),
    );
  }
}

// Lifetime savings balance shown beside the action buttons.
class _TotalSavingsCard extends StatelessWidget {
  final double total;

  const _TotalSavingsCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'إجمالي المبالغ الموفرة',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),

          const SizedBox(height: 4),

          if (total <= 0)
            Text(
              'وفّر أول مبلغ ليظهر هنا',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary.withValues(alpha: 0.65),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: RollingMoney(
                      value: total,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    currencyLabel,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// Compact glass button used for save/withdraw and plan shortcuts.
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Empty-state CTA that opens the create-goal sheet.
class _CreateGoalCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _CreateGoalCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      onTap: onCreate,
      colorType: GlassColorType.accent, tintOpacity: 9, 
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: Text(
          'إنشاء هدف',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppPalette.of(context).onAccent,
          ),
        ),
      ),
    );
  }
}

// Name, progress bar, and saved/target amounts for one active goal.
class _GoalProgressCard extends StatelessWidget {
  final SavingsGoal goal;
  final double saved;

  const _GoalProgressCard({
    required this.goal,
    required this.saved,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);

    final ratio = goal.targetAmount <= 0
        ? 0.0
        : (saved / goal.targetAmount).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          goal.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),

        const SizedBox(height: 10),

        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _HorizontalProgress(
                ratio: ratio,
                height: 18,
                trackColor: colors.textPrimary.withValues(alpha: 0.08),
                fillColor: colors.accent,
              ),
            ),

            const SizedBox(width: 10),

            Text(
              '${(ratio * 100).round()}%',
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${formatMoney(saved)} / ${formatMoney(goal.targetAmount)}',
                ),
                TextSpan(
                  text: ' $currencyLabel',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: const ['Tajawal'],
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// Rounded track with a fractionally filled accent bar.
class _HorizontalProgress extends StatelessWidget {
  final double ratio;
  final double height;
  final Color trackColor;
  final Color fillColor;

  const _HorizontalProgress({
    required this.ratio,
    required this.trackColor,
    required this.fillColor,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: trackColor)),

            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedRatio(
                value: ratio,
                builder: (context, shown) => FractionallySizedBox(
                  widthFactor: shown,
                  child: Container(
                    height: height,
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
            ),
          ],
        ),
      ),
    );
  }
}
