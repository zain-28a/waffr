// Savings log sheet: every move into and out of savings, newest first.
// Moves the user made by hand can be edited or deleted; automatic ones
// (period leftovers, plan deductions) are listed but locked.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/report/edit_transaction_sheet.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/containers/swipe_actions.dart';

/// Opens the savings log for the active currency.
Future<void> showSavingsLogSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    heightFactor: 0.78,
    builder: (_) => const _SavingsLogSheet(),
  );
}

class _SavingsLogSheet extends StatelessWidget {
  const _SavingsLogSheet();

  @override
  Widget build(BuildContext context) {
    final store = TransactionStore.instance;
    final divider = AppPalette.of(context).textSecondary
        .withValues(alpha: 0.12);

    return GlassSheetFixedBody(
      header: const GlassSheetHeader(
        title: 'سجل التوفير',
        subtitle: 'اضغط عملية يدوية لتعديلها، أو اسحبها للحذف.',
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final moves = store.savingsTransfers;
          if (moves.isEmpty) {
            return const Center(
              child: AppEmptyState(
                icon: AppIcons.piggyBank,
                title: 'لا توجد عمليات توفير بعد',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            itemCount: moves.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, thickness: 1, color: divider),
            itemBuilder: (context, index) {
              final move = moves[index];
              final editable = store.isEditableTransfer(move);
              return SwipeActions(
                key: ValueKey(move.id),
                enabled: editable,
                actions: [
                  SwipeAction(
                    icon: AppIcons.edit,
                    label: 'تعديل',
                    onTap: () => showEditTransactionSheet(context, move),
                  ),
                  SwipeAction(
                    icon: AppIcons.trash,
                    label: 'حذف',
                    destructive: true,
                    onTap: () => confirmDeleteTransaction(context, move),
                  ),
                ],
                child: _MoveRow(
                  move: move,
                  editable: editable,
                  onTap: editable
                      ? () => showEditTransactionSheet(context, move)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One savings move: direction mark, what it was, when, and how much.
class _MoveRow extends StatelessWidget {
  final WaffrTransaction move;
  final bool editable;
  final VoidCallback? onTap;

  const _MoveRow({
    required this.move,
    required this.editable,
    required this.onTap,
  });

  String get _title => switch (move.transferKind) {
    SavingsTransferKind.manual => 'توفير يدوي',
    SavingsTransferKind.withdraw => 'سحب إلى الرصيد',
    SavingsTransferKind.periodLeftover => 'متبقي الفترة',
    SavingsTransferKind.goalPeriodic => 'خطة التوفير',
    null => move.isSavingsOut ? 'سحب إلى الرصيد' : 'توفير',
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final out = move.isSavingsOut;
    final date = move.dateTime.toLocal();
    final tone = out ? palette.textSecondary : palette.accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(
                out ? AppIcons.withdraw : AppIcons.deposit,
                size: 20,
                color: tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day} ${CalendarPeriod.monthName(date.month)} '
                    '${date.year}${editable ? '' : ' · تلقائي'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${out ? '−' : '+'}${formatMoney(move.amount)} '
              '${currencyLabelFor(move.currencyCode)}',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontFamilyFallback: const ['Tajawal'],
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: out ? palette.textPrimary : palette.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!editable) ...[
              const SizedBox(width: 6),
              Icon(AppIcons.lock, size: 13, color: palette.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
