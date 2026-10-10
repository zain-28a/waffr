// Obligations: the list of recurring expenses, the details of one, and the
// sheet where charges waiting for approval are deducted or postponed.

import 'package:flutter/material.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/data/models/calendar_period.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/recurring_expense.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/stores/recurring_expense_store.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';
import 'package:waffer/widgets/dialogs/edit_amount_dialog.dart';

const String kDeductAutomaticLabel = 'تلقائي';
const String kDeductConfirmLabel = 'بعد تأكيدي';

const String kDeductModeInfoTitle = 'طريقة الخصم';
const String kDeductModeInfoMessage =
    'تلقائي: يُخصم المبلغ من رصيدك في موعده دون أن نسألك. يناسب من لديه راتب ثابت.\n\n'
    'بعد تأكيدي: عند حلول الموعد يصلك تنبيه، وتختار بنفسك خصم المبلغ أو تأجيله. '
    'يناسب من يكون دخله غير منتظم، مثل العمل الحر.';

Future<void> showObligationsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const ObligationsSheet(),
  );
}

Future<void> showDueObligationsSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const DueObligationsSheet(),
  );
}

// Name shown for an obligation: its note, else its category.
String obligationTitle(RecurringExpense item) {
  final note = item.note?.trim() ?? '';
  return note.isEmpty ? categoryFor(item.category).label : note;
}

// "12 تشرين الأول", or today / tomorrow.
String obligationDate(DateTime date, {DateTime? now}) {
  final moment = now ?? deviceNow();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(moment.year, moment.month, moment.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غداً';
  final month = CalendarPeriod.monthName(date.month);
  return date.year == moment.year
      ? '${date.day} $month'
      : '${date.day} $month ${date.year}';
}

String paymentsLabel(int count) {
  if (count == 1) return 'دفعة واحدة';
  if (count == 2) return 'دفعتان';
  if (count <= 10) return '$count دفعات';
  return '$count دفعة';
}

String obligationsCountLabel(int count) {
  if (count == 1) return 'التزام واحد';
  if (count == 2) return 'التزامان';
  if (count <= 10) return '$count التزامات';
  return '$count التزاماً';
}

// One line describing where an obligation stands right now. [short] is for
// narrow places such as the home card.
String obligationStatus(
  RecurringExpense item, {
  DateTime? now,
  bool short = false,
}) {
  final moment = now ?? deviceNow();
  if (!item.enabled) return 'متوقف';

  final due = item.dueDates(moment).length;
  if (due > 0) {
    if (!item.requiresConfirmation) {
      return short ? 'الرصيد غير كافٍ' : 'لم يُخصم لأن الرصيد غير كافٍ';
    }
    if (item.remindOnIncome) {
      return short ? 'مؤجل' : 'مؤجل حتى إضافة دخل جديد';
    }
    final remindAt = item.remindAt;
    if (remindAt != null && remindAt.isAfter(moment)) {
      return short
          ? 'مؤجل'
          : 'مؤجل، نذكّرك ${obligationDate(remindAt, now: moment)}';
    }
    return due == 1 || short
        ? 'بانتظار تأكيدك'
        : 'بانتظار تأكيدك (${paymentsLabel(due)})';
  }

  final date = obligationDate(item.nextDueAt, now: moment);
  return short ? date : 'الدفعة القادمة $date';
}

// True when the obligation has a charge that has not been deducted yet.
bool obligationNeedsAttention(RecurringExpense item, {DateTime? now}) {
  return item.enabled &&
      item.dueDates(now ?? deviceNow(), max: 1).isNotEmpty;
}

class _ObligationColors {
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color warning;

  const _ObligationColors({
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.warning,
  });

  factory _ObligationColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ObligationColors(
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      textPrimary:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      textSecondary:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      warning: isDark ? const Color(0xFFE2C27A) : const Color(0xFF8A6A24),
    );
  }
}

TextStyle _text(
  Color color, {
  double size = 13,
  FontWeight weight = FontWeight.w500,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: const ['Tajawal'],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
  );
}

// ---------------------------------------------------------------------------
// Obligations list
// ---------------------------------------------------------------------------

class ObligationsSheet extends StatefulWidget {
  const ObligationsSheet({super.key});

  @override
  State<ObligationsSheet> createState() => _ObligationsSheetState();
}

class _ObligationsSheetState extends State<ObligationsSheet> {
  final RecurringExpenseStore _store = RecurringExpenseStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ObligationColors.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_store, CurrencyStore.instance]),
      builder: (context, _) {
        final code = CurrencyStore.instance.activeCode;
        final now = deviceNow();
        final items = _sorted(_store.itemsFor(code), now);
        final awaiting = _store.awaitingConfirmation(code, now: now);
        final next = _store.nextUpcoming(code, now: now);
        final symbol = currencyLabelFor(code);

        return GlassSheetBody(
          children: [
            const GlassSheetHeader(
              title: 'الالتزامات',
              subtitle: 'المصروفات التي تتكرر بانتظام، مثل الإيجار والاشتراكات.',
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              _EmptyObligations(colors: colors)
            else ...[
              _SummaryBox(
                colors: colors,
                monthlyTotal:
                    '${formatMoney(_store.monthlyTotal(code))} $symbol',
                nextLine: next == null
                    ? null
                    : '${obligationTitle(next)}، ${obligationDate(next.nextDueAt, now: now)}',
              ),
              if (awaiting.isNotEmpty) ...[
                const SizedBox(height: 10),
                _AwaitingBanner(
                  colors: colors,
                  count: awaiting.length,
                  onTap: () => showDueObligationsSheet(context),
                ),
              ],
              const SizedBox(height: 16),
              const SheetFieldLabel(text: 'كل الالتزامات'),
              for (final item in items) ...[
                _ObligationTile(
                  item: item,
                  colors: colors,
                  now: now,
                  onTap: () => _openDetails(item),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }

  // Waiting charges first, then by next charge date; stopped ones last.
  List<RecurringExpense> _sorted(List<RecurringExpense> items, DateTime now) {
    int rank(RecurringExpense item) {
      if (!item.enabled) return 2;
      return obligationNeedsAttention(item, now: now) ? 0 : 1;
    }

    final list = [...items];
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.nextDueAt.compareTo(b.nextDueAt);
    });
    return list;
  }

  void _openDetails(RecurringExpense item) {
    showGlassSheet<void>(
      context: context,
      builder: (context) => _ObligationDetailsSheet(id: item.id),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final _ObligationColors colors;
  final String monthlyTotal;
  final String? nextLine;

  const _SummaryBox({
    required this.colors,
    required this.monthlyTotal,
    required this.nextLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: sheetFieldColor(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المجموع الشهري التقريبي',
            style: _text(colors.textSecondary, size: 12.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            monthlyTotal,
            style: _text(colors.accent, size: 22, weight: FontWeight.bold),
          ),
          if (nextLine != null) ...[
            const SizedBox(height: 6),
            Text(
              'الدفعة القادمة: $nextLine',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(colors.textSecondary, size: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _AwaitingBanner extends StatelessWidget {
  final _ObligationColors colors;
  final int count;
  final VoidCallback onTap;

  const _AwaitingBanner({
    required this.colors,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(Icons.pending_actions_rounded, size: 22, color: colors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? 'لديك التزام بانتظار تأكيدك'
                      : 'لديك ${obligationsCountLabel(count)} بانتظار تأكيدك',
                  style: _text(colors.textPrimary, size: 13.5, weight: FontWeight.w700),
                ),
              ),
              Text(
                'مراجعة',
                style: _text(colors.warning, size: 13, weight: FontWeight.w700),
              ),
              Icon(Icons.chevron_left_rounded, color: colors.warning),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyObligations extends StatelessWidget {
  final _ObligationColors colors;

  const _EmptyObligations({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            'لا توجد التزامات بعد',
            style: _text(colors.textPrimary, size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'لإضافة التزام، اختر «إضافة مصروف» ثم «مصروف متكرر».',
            textAlign: TextAlign.center,
            style: _text(colors.textSecondary, size: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ObligationTile extends StatelessWidget {
  final RecurringExpense item;
  final _ObligationColors colors;
  final DateTime now;
  final VoidCallback onTap;

  const _ObligationTile({
    required this.item,
    required this.colors,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final attention = obligationNeedsAttention(item, now: now);
    final category = categoryFor(item.category);
    final statusColor = attention ? colors.warning : colors.textSecondary;

    return Opacity(
      opacity: item.enabled ? 1 : 0.6,
      child: Material(
        color: sheetFieldColor(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent.withValues(alpha: 0.12),
                  ),
                  child: Icon(category.icon, size: 19, color: colors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        obligationTitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(colors.textPrimary, size: 14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)} · ${item.intervalDescription} · '
                        '${item.requiresConfirmation ? kDeductConfirmLabel : kDeductAutomaticLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(colors.textSecondary, size: 11.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        obligationStatus(item, now: now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          statusColor,
                          size: 11.5,
                          weight: attention ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One obligation
// ---------------------------------------------------------------------------

class _ObligationDetailsSheet extends StatefulWidget {
  final String id;

  const _ObligationDetailsSheet({required this.id});

  @override
  State<_ObligationDetailsSheet> createState() =>
      _ObligationDetailsSheetState();
}

class _ObligationDetailsSheetState extends State<_ObligationDetailsSheet> {
  final RecurringExpenseStore _store = RecurringExpenseStore.instance;

  static const String _activeLabel = 'مفعّل';
  static const String _stoppedLabel = 'متوقف';

  Future<void> _editAmount(RecurringExpense item) async {
    final colors = _ObligationColors.of(context);
    final result = await showAppDialog<Object>(
      context: context,
      builder: (context) => EditAmountDialog(
        title: obligationTitle(item),
        initialAmount: item.amount,
        accent: colors.accent,
        currencyCode: item.currencyCode,
      ),
    );

    if (!mounted || result is! EditAmountResult) return;

    final saved = await _store.updateAmount(
      item.id,
      result.amount,
      currencyCode: result.currencyCode,
    );
    if (!mounted) return;

    if (!saved) {
      showAppSnackBar(context, 'تعذّر حفظ المبلغ. حاول مرة أخرى.');
      return;
    }
    showAppSnackBar(context, 'تم حفظ المبلغ الجديد', success: true);
  }

  Future<void> _delete(RecurringExpense item) async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'حذف الالتزام',
      message:
          'سيُحذف «${obligationTitle(item)}» ولن يُخصم مرة أخرى. المصروفات التي خُصمت سابقاً تبقى في السجل.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (confirm != true) return;

    await _store.deleteExpense(item.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ObligationColors.of(context);

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final item = _store.byId(widget.id);
        if (item == null) {
          return const GlassSheetBody(
            children: [
              GlassSheetHeader(
                title: 'الالتزام',
                subtitle: 'لم يعد هذا الالتزام موجوداً.',
              ),
              SizedBox(height: 12),
            ],
          );
        }

        final now = deviceNow();
        final attention = obligationNeedsAttention(item, now: now);
        final awaiting = attention && item.requiresConfirmation;

        return GlassSheetBody(
          children: [
            GlassSheetHeader(
              title: obligationTitle(item),
              subtitle:
                  '${categoryFor(item.category).label} · ${item.intervalDescription}',
            ),
            const SizedBox(height: 18),
            const SheetFieldLabel(text: 'المبلغ'),
            Material(
              color: sheetFieldColor(context),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _editAmount(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}',
                          style: _text(colors.textPrimary, size: 17, weight: FontWeight.bold),
                        ),
                      ),
                      Icon(Icons.edit_rounded, size: 19, color: colors.accent),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SheetFieldLabel(
              text: 'طريقة الخصم',
              action: SheetInfoButton(
                title: kDeductModeInfoTitle,
                message: kDeductModeInfoMessage,
              ),
            ),
            SheetChoiceChips(
              options: const [kDeductAutomaticLabel, kDeductConfirmLabel],
              selected: item.requiresConfirmation
                  ? kDeductConfirmLabel
                  : kDeductAutomaticLabel,
              onSelected: (value) => _store.setRequiresConfirmation(
                item.id,
                value == kDeductConfirmLabel,
              ),
            ),
            const SizedBox(height: 16),
            const SheetFieldLabel(text: 'الحالة'),
            SheetChoiceChips(
              options: const [_activeLabel, _stoppedLabel],
              selected: item.enabled ? _activeLabel : _stoppedLabel,
              onSelected: (value) =>
                  _store.setEnabled(item.id, value == _activeLabel),
            ),
            const SizedBox(height: 10),
            Text(
              obligationStatus(item, now: now),
              textAlign: TextAlign.center,
              style: _text(
                attention ? colors.warning : colors.textSecondary,
                size: 12.5,
                weight: attention ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            if (awaiting) ...[
              SheetSaveButton(
                label: 'مراجعة وتأكيد',
                onTap: () {
                  Navigator.of(context).maybePop();
                  showDueObligationsSheet(context);
                },
              ),
              const SizedBox(height: 8),
            ],
            TextButton.icon(
              onPressed: () => _delete(item),
              icon: const Icon(Icons.delete_outline_rounded, color: _deleteColor),
              label: Text(
                'حذف الالتزام',
                style: _text(_deleteColor, size: 14, weight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }
}

const Color _deleteColor = Color(0xFFD3544D);

// ---------------------------------------------------------------------------
// Charges waiting for approval
// ---------------------------------------------------------------------------

enum _DueAction { deductOne, deductAll, postpone }

enum _PostponeOption { day, threeDays, week, nextIncome }

extension on _PostponeOption {
  String get label => switch (this) {
        _PostponeOption.day => 'يوم',
        _PostponeOption.threeDays => '3 أيام',
        _PostponeOption.week => 'أسبوع',
        _PostponeOption.nextIncome => 'دخل جديد',
      };
}

class DueObligationsSheet extends StatefulWidget {
  const DueObligationsSheet({super.key});

  @override
  State<DueObligationsSheet> createState() => _DueObligationsSheetState();
}

class _DueObligationsSheetState extends State<DueObligationsSheet> {
  final RecurringExpenseStore _store = RecurringExpenseStore.instance;

  final Map<String, _DueAction> _actions = {};
  final Map<String, _PostponeOption> _postpone = {};
  bool _saving = false;

  // Snapshot so items do not vanish while the user is choosing.
  List<RecurringExpense>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    if (!mounted) return;
    final now = deviceNow();
    final items = <RecurringExpense>[];
    for (final code in {for (final item in _store.items) item.currencyCode}) {
      items.addAll(_store.awaitingConfirmation(code, now: now));
    }
    items.sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    setState(() => _items = items);
  }

  Future<void> _confirm() async {
    final items = _items ?? const [];
    if (_saving || items.isEmpty) return;
    setState(() => _saving = true);

    var deducted = 0;
    var shortOfBalance = false;
    var postponed = 0;

    for (final item in items) {
      final action = _actions[item.id] ?? _DueAction.deductOne;
      switch (action) {
        case _DueAction.deductOne:
        case _DueAction.deductAll:
          final all = action == _DueAction.deductAll;
          final wanted = all ? item.dueDates(deviceNow()).length : 1;
          final posted = await _store.confirmDue(item.id, all: all);
          deducted += posted;
          if (posted < wanted) shortOfBalance = true;
        case _DueAction.postpone:
          final option = _postpone[item.id] ?? _PostponeOption.day;
          await _store.postpone(
            item.id,
            untilIncome: option == _PostponeOption.nextIncome,
            after: switch (option) {
              _PostponeOption.day => const Duration(days: 1),
              _PostponeOption.threeDays => const Duration(days: 3),
              _PostponeOption.week => const Duration(days: 7),
              _PostponeOption.nextIncome => null,
            },
          );
          postponed++;
      }
    }

    if (!mounted) return;
    Navigator.of(context).maybePop();

    if (shortOfBalance) {
      showAppSnackBar(
        context,
        'رصيدك لا يكفي لخصم بعض الدفعات، فبقيت بانتظار تأكيدك.',
        kind: AppFeedbackKind.warning,
      );
    } else if (deducted > 0 && postponed > 0) {
      showAppSnackBar(context, 'تم الخصم والتأجيل كما اخترت', success: true);
    } else if (deducted > 0) {
      showAppSnackBar(context, 'تم خصم المبلغ من رصيدك', success: true);
    } else {
      showAppSnackBar(
        context,
        'تم التأجيل، وسنذكّرك في الموعد الذي اخترته',
        kind: AppFeedbackKind.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ObligationColors.of(context);
    final items = _items;

    return GlassSheetBody(
      children: [
        const GlassSheetHeader(
          title: 'التزامات بانتظار تأكيدك',
          subtitle: 'اختر لكل التزام: خصم المبلغ الآن أو تأجيله إلى وقت لاحق.',
        ),
        const SizedBox(height: 16),
        if (items == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  size: 42,
                  color: colors.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 10),
                Text(
                  'لا توجد التزامات بانتظار تأكيدك',
                  style: _text(colors.textPrimary, size: 14, weight: FontWeight.w700),
                ),
              ],
            ),
          )
        else ...[
          for (final item in items) ...[
            _DueItemCard(
              item: item,
              colors: colors,
              action: _actions[item.id] ?? _DueAction.deductOne,
              postpone: _postpone[item.id] ?? _PostponeOption.day,
              onAction: (value) => setState(() => _actions[item.id] = value),
              onPostpone: (value) => setState(() => _postpone[item.id] = value),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          SheetSaveButton(
            label: 'تأكيد',
            enabled: !_saving,
            onTap: _confirm,
          ),
        ],
      ],
    );
  }
}

class _DueItemCard extends StatelessWidget {
  final RecurringExpense item;
  final _ObligationColors colors;
  final _DueAction action;
  final _PostponeOption postpone;
  final ValueChanged<_DueAction> onAction;
  final ValueChanged<_PostponeOption> onPostpone;

  static const String _deductLabel = 'خصم';
  static const String _deductOneLabel = 'خصم دفعة';
  static const String _deductAllLabel = 'خصم الكل';
  static const String _postponeLabel = 'تأجيل';

  const _DueItemCard({
    required this.item,
    required this.colors,
    required this.action,
    required this.postpone,
    required this.onAction,
    required this.onPostpone,
  });

  @override
  Widget build(BuildContext context) {
    final count = item.dueDates(deviceNow()).length;
    final symbol = currencyLabelFor(item.currencyCode);
    final several = count > 1;

    final options = several
        ? const [_deductOneLabel, _deductAllLabel, _postponeLabel]
        : const [_deductLabel, _postponeLabel];
    final selected = switch (action) {
      _DueAction.postpone => _postponeLabel,
      _DueAction.deductAll => several ? _deductAllLabel : _deductLabel,
      _DueAction.deductOne => several ? _deductOneLabel : _deductLabel,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.textSecondary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  obligationTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(colors.textPrimary, size: 15, weight: FontWeight.bold),
                ),
              ),
              Text(
                '${formatMoney(item.amount)} $symbol',
                style: _text(colors.accent, size: 15, weight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            several
                ? 'مستحق عن ${paymentsLabel(count)}، المجموع ${formatMoney(item.amount * count)} $symbol'
                : 'موعده ${obligationDate(item.nextDueAt)}',
            style: _text(colors.textSecondary, size: 12),
          ),
          const SizedBox(height: 10),
          SheetChoiceChips(
            options: options,
            selected: selected,
            onSelected: (value) => onAction(switch (value) {
              _postponeLabel => _DueAction.postpone,
              _deductAllLabel => _DueAction.deductAll,
              _ => _DueAction.deductOne,
            }),
          ),
          SheetExpand(
            visible: action == _DueAction.postpone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const SheetFieldLabel(text: 'ذكّرني بعد'),
                SheetChoiceChips(
                  options: [for (final option in _PostponeOption.values) option.label],
                  selected: postpone.label,
                  onSelected: (value) => onPostpone(
                    _PostponeOption.values.firstWhere(
                      (option) => option.label == value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
