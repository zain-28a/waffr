import 'package:flutter/material.dart';
import 'package:waffer/core/data/recurring_expense.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showRecurringExpensesSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const RecurringExpensesSheet(),
  );
}

class RecurringExpensesPreviewCard extends StatefulWidget {
  const RecurringExpensesPreviewCard({super.key});

  @override
  State<RecurringExpensesPreviewCard> createState() =>
      _RecurringExpensesPreviewCardState();
}

class _RecurringExpensesPreviewCardState
    extends State<RecurringExpensesPreviewCard> {
  final RecurringExpenseStore _store = RecurringExpenseStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final colors = _RecurringColors.of(context);
        final preview = _store.items.take(3).toList(growable: false);

        return GlassButton(
          onTap: () => showRecurringExpensesSheet(context),
          colorType: GlassColorType.surface,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.event_repeat_rounded,
                      size: 21,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المصروفات المتكررة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          preview.isEmpty
                              ? 'لا يوجد اشتراك أو مصروف متكرر'
                              : '${_store.items.length} عناصر محفوظة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final item in preview)
                  _PreviewItem(item: item, colors: colors),
                if (_store.items.length > preview.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${_store.items.length - preview.length} عناصر أخرى',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class RecurringExpensesSheet extends StatefulWidget {
  const RecurringExpensesSheet({super.key});

  @override
  State<RecurringExpensesSheet> createState() => _RecurringExpensesSheetState();
}

class _RecurringExpensesSheetState extends State<RecurringExpensesSheet> {
  final RecurringExpenseStore _store = RecurringExpenseStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  Future<void> _delete(RecurringExpense item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('حذف المصروف المتكرر'),
          content: const Text('سيتم إيقاف الخصم التلقائي لهذا المصروف.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'حذف',
                style: TextStyle(
                  color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    await _store.deleteExpense(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _RecurringColors.of(context);

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return GlassSheetBody(
          children: [
            const GlassSheetHeader(
              title: 'المصروفات المتكررة',
              subtitle: 'الاشتراكات والمصروفات التي تُخصم تلقائياً من رصيدك.',
            ),
            const SizedBox(height: 16),
            if (_store.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_repeat_outlined,
                      size: 42,
                      color: colors.textSecondary.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'لا توجد مصروفات متكررة بعد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final item in _store.items) ...[
                _RecurringItemTile(
                  item: item,
                  colors: colors,
                  onToggle: (enabled) => _store.setEnabled(item.id, enabled),
                  onDelete: () => _delete(item),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _PreviewItem extends StatelessWidget {
  final RecurringExpense item;
  final _RecurringColors colors;

  const _PreviewItem({required this.item, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            item.enabled
                ? Icons.repeat_rounded
                : Icons.pause_circle_outline_rounded,
            size: 17,
            color: item.enabled
                ? colors.accent
                : colors.textSecondary.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.note ?? item.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                color: item.enabled ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
          Text(
            item.intervalDescription,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringItemTile extends StatelessWidget {
  final RecurringExpense item;
  final _RecurringColors colors;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _RecurringItemTile({
    required this.item,
    required this.colors,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: sheetFieldColor(context),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.note ?? item.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatMoney(item.amount)} $currencyLabel · ${item.intervalDescription}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: item.enabled,
              activeThumbColor: colors.accent,
              onChanged: onToggle,
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringColors {
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _RecurringColors({
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _RecurringColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _RecurringColors(
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      textPrimary: isDark
          ? AppColors.darkTextPrimary
          : AppColors.lightTextPrimary,
      textSecondary: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
    );
  }
}
