// Home recent activity (part of dashboard.dart): the latest expenses as a
// list, and the obligations that are due or coming up.

part of 'dashboard.dart';

/// "Today", "Yesterday", or the day and month for older entries.
String _dayLabel(DateTime date, DateTime now) {
  final local = date.toLocal();
  final days = calendarDaysBetween(
    DateTime(local.year, local.month, local.day),
    DateTime(now.year, now.month, now.day),
  );
  if (days == 0) return 'اليوم';
  if (days == 1) return 'أمس';
  return '${local.day} ${CalendarPeriod.monthName(local.month)}';
}

/// The last few expenses. The header opens the full history.
class _RecentCard extends StatelessWidget {
  final List<WaffrTransaction> expenses;
  final VoidCallback onAll;

  const _RecentCard({required this.expenses, required this.onAll});

  static const int _shown = 4;

  @override
  Widget build(BuildContext context) {
    final recent = expenses.take(_shown).toList(growable: false);
    final now = deviceNow();
    final divider = AppPalette.of(context).textSecondary
        .withValues(alpha: 0.12);

    return _SectionCard(
      title: 'آخر المصروفات',
      action: 'عرض الكل',
      onTap: onAll,
      child: recent.isEmpty
          ? const _EmptyState(
              icon: AppIcons.receipt,
              message: 'لا يوجد مصروف مسجّل بعد',
            )
          : Column(
              children: [
                for (final (index, expense) in recent.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 56),
                      child: Divider(height: 1, thickness: 1, color: divider),
                    ),
                  _ExpenseRow(expense: expense, now: now),
                ],
              ],
            ),
    );
  }
}

/// One expense: category mark, what it was, when, and how much.
class _ExpenseRow extends StatelessWidget {
  final WaffrTransaction expense;
  final DateTime now;

  const _ExpenseRow({required this.expense, required this.now});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final category = categoryFor(expense.category);
    final color = categoryChartColor(context, expense.category);
    final note = expense.note?.trim() ?? '';
    final recurring = RecurringExpense.isRecurringSource(expense.sourceId);

    // A tap opens the editor for this expense.
    return Semantics(
      button: true,
      hint: 'تعديل',
      child: Pressable(
        onTap: () => showEditTransactionSheet(context, expense),
        depth: 0.02,
        child: _content(palette, category, color, note, recurring),
      ),
    );
  }

  Widget _content(
    AppPalette palette,
    ExpenseCategory category,
    Color color,
    String note,
    bool recurring,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _CategoryMark(icon: category.icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isEmpty ? category.label : note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    14.5,
                    weight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (recurring) ...[
                      Icon(
                        AppIcons.repeat,
                        size: 12,
                        color: palette.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        '${category.label} · '
                        '${_dayLabel(expense.dateTime, now)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(12, color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Amount(
            amount: expense.amount,
            symbol: currencyLabel,
            color: palette.textPrimary,
            unitColor: palette.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Round category mark: the icon on a soft tint of the category color.
class _CategoryMark extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _CategoryMark({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}

/// An amount with its currency: the number is the loud part.
class _Amount extends StatelessWidget {
  final double amount;
  final String symbol;
  final Color color;
  final Color unitColor;

  const _Amount({
    required this.amount,
    required this.symbol,
    required this.color,
    required this.unitColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatMoney(amount),
            style: _text(
              15.5,
              weight: FontWeight.w700,
              color: color,
              tabular: true,
            ),
          ),
          TextSpan(
            text: ' $symbol',
            style: _text(11.5, color: unitColor),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// Up to two obligations: those waiting for the user first, then the next
/// ones due. Hidden when there are none. Opens the obligations sheet.
class _ObligationsCard extends StatelessWidget {
  final List<RecurringExpense> obligations;
  final VoidCallback onTap;

  const _ObligationsCard({required this.obligations, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = deviceNow();
    final active = obligations.where((item) => item.enabled).toList()
      ..sort((a, b) {
        final aFirst = obligationNeedsAttention(a, now: now) ? 0 : 1;
        final bFirst = obligationNeedsAttention(b, now: now) ? 0 : 1;
        if (aFirst != bFirst) return aFirst.compareTo(bFirst);
        return a.nextDueAt.compareTo(b.nextDueAt);
      });
    if (active.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final divider = palette.textSecondary.withValues(alpha: 0.12);
    final shown = active.take(2).toList(growable: false);

    return _SectionCard(
      title: 'الالتزامات',
      action: active.length > shown.length ? 'الكل (${active.length})' : null,
      onTap: onTap,
      child: Column(
        children: [
          for (final (index, item) in shown.indexed) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 56),
                child: Divider(height: 1, thickness: 1, color: divider),
              ),
            _ObligationRow(item: item, now: now),
          ],
        ],
      ),
    );
  }
}

/// One obligation, styled like [_ExpenseRow]. The status line turns to the
/// warning color when the obligation needs the user's attention.
class _ObligationRow extends StatelessWidget {
  final RecurringExpense item;
  final DateTime now;

  const _ObligationRow({required this.item, required this.now});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final category = categoryFor(item.category);
    final attention = obligationNeedsAttention(item, now: now);
    final color = attention
        ? AppColors.warningOf(context)
        : categoryChartColor(context, item.category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _CategoryMark(icon: category.icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obligationTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    14.5,
                    weight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  obligationStatus(item, now: now, short: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    12,
                    weight: attention ? FontWeight.w700 : FontWeight.w400,
                    color: attention
                        ? AppColors.warningOf(context)
                        : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Amount in the obligation's own currency.
          _Amount(
            amount: item.amount,
            symbol: currencyLabelFor(item.currencyCode),
            color: palette.textPrimary,
            unitColor: palette.textSecondary,
          ),
        ],
      ),
    );
  }
}
