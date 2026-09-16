import 'package:flutter/material.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showCompletedGoalsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _CompletedGoalsSheet(),
  );
}

class _CompletedGoalsSheet extends StatefulWidget {
  const _CompletedGoalsSheet();

  @override
  State<_CompletedGoalsSheet> createState() => _CompletedGoalsSheetState();
}

class _CompletedGoalsSheetState extends State<_CompletedGoalsSheet> {
  final TransactionStore _store = TransactionStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final goals = _store.completedGoals;

    return GlassSheetBody(
      children: [
        const GlassSheetHeader(
          title: 'الأهداف المحققة',
          subtitle: 'سجل الأهداف التي اكتملت.',
        ),
        const SizedBox(height: 12),
        if (goals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 38,
                  color: textPrimary.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 10),
                Text(
                  'لا توجد أهداف محققة بعد',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 14,
                    color: textPrimary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          )
        else
          for (final goal in goals) ...[
            _CompletedGoalCard(
              goal: goal,
              accent: accent,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _CompletedGoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _CompletedGoalCard({
    required this.goal,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final total = goal.completedAmount ?? goal.targetAmount;
    final completed = goal.completedAt;

    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            goal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'المستهدف: ${formatMoney(goal.targetAmount)} $currencyLabel',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: textSecondary,
            ),
          ),
          Text(
            'المتجمّع: ${formatMoney(total)} $currencyLabel',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'المدة: ${goal.duration.label}',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12.5,
              color: textSecondary,
            ),
          ),
          if (completed != null)
            Text(
              'تاريخ الإنجاز: ${formatDate(completed)}',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 12.5,
                color: textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
