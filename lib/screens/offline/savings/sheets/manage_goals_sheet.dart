import 'package:flutter/material.dart';
import 'package:waffer/core/data/savings_goal.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showManageGoalsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _ManageGoalsSheet(),
  );
}

class _ManageGoalsSheet extends StatefulWidget {
  const _ManageGoalsSheet();

  @override
  State<_ManageGoalsSheet> createState() => _ManageGoalsSheetState();
}

class _ManageGoalsSheetState extends State<_ManageGoalsSheet> {
  final TransactionStore _store = TransactionStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  Future<void> _confirmDelete(SavingsGoal goal) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: Text(
            'حذف الهدف',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          content: const Text(
            'هل أنت متأكد من حذف هذا الهدف؟',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'إلغاء',
                style: TextStyle(fontFamily: 'Tajawal', color: textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'حذف',
                style: TextStyle(fontFamily: 'Tajawal', color: accent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _store.deleteGoal(goal.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return GlassContainer(
      colorType: GlassColorType.surface,
      tintOpacity: 1,
      radius: const BorderRadius.vertical(top: Radius.circular(34)),
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: AnimatedBuilder(
            animation: _store,
            builder: (context, _) {
              final goals = _store.activeGoals;
              final maxListHeight = MediaQuery.sizeOf(context).height * 0.48;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GlassSheetHeader(
                    title: 'إدارة الأهداف',
                    subtitle: 'اسحب لتغيير الأولوية، أو أضف هدفاً جديداً.',
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxListHeight),
                    child: goals.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Text(
                              'لا توجد أهداف حالياً',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 14,
                                color: textPrimary.withValues(alpha: 0.55),
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            shrinkWrap: true,
                            primary: false,
                            buildDefaultDragHandles: false,
                            padding: EdgeInsets.zero,
                            itemCount: goals.length,
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (context, _) {
                                  final t = Curves.easeOut.transform(
                                    animation.value,
                                  );
                                  return Material(
                                    color: Colors.transparent,
                                    elevation: 4 * t,
                                    borderRadius: BorderRadius.circular(22),
                                    child: child,
                                  );
                                },
                              );
                            },
                            onReorderItem: _store.reorderActiveGoals,
                            itemBuilder: (context, index) {
                              final goal = goals[index];
                              return Padding(
                                key: ValueKey(goal.id),
                                padding: EdgeInsets.only(
                                  bottom: index == goals.length - 1 ? 0 : 10,
                                ),
                                child: _ManageGoalRow(
                                  index: index,
                                  goal: goal,
                                  saved: _store.currentSaved(goal),
                                  accent: accent,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  onDelete: () => _confirmDelete(goal),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: accent,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => showCreateGoalSheet(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'إضافة هدف',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.add_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ManageGoalRow extends StatelessWidget {
  final int index;
  final SavingsGoal goal;
  final double saved;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onDelete;

  const _ManageGoalRow({
    required this.index,
    required this.goal,
    required this.saved,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = goal.targetAmount <= 0
        ? 0.0
        : (saved / goal.targetAmount).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: sheetFieldColor(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Icon(
                Icons.drag_handle_rounded,
                color: textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  goal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: textPrimary.withValues(alpha: 0.08),
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatMoney(saved)} / ${formatMoney(goal.targetAmount)}'
                  '  ·  ${(ratio * 100).round()}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: textPrimary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onDelete,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: textPrimary.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
