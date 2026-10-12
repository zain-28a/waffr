// Obligation labels: the shared Arabic captions, titles, dates, counts and
// status lines used by every obligations view.

part of 'obligations_sheet.dart';

const String kDeductAutomaticLabel = 'تلقائي';

const String kDeductConfirmLabel = 'بعد تأكيدي';

const String kDeductModeInfoTitle = 'طريقة الخصم';

const String kDeductModeInfoMessage =
    'تلقائي: يُخصم المبلغ من رصيدك في موعده دون أن نسألك. يناسب من لديه راتب ثابت.\n\n'
    'بعد تأكيدي: عند حلول الموعد يصلك تنبيه، وتختار بنفسك خصم المبلغ أو تأجيله. '
    'يناسب من يكون دخله غير منتظم، مثل العمل الحر.';

/// Name shown for an obligation: its note, else its category.
String obligationTitle(RecurringExpense item) {
  final note = item.note?.trim() ?? '';
  return note.isEmpty ? categoryFor(item.category).label : note;
}

/// "12 تشرين الأول", or today / tomorrow.
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

/// One line describing where an obligation stands right now. [short] is for
/// narrow places such as the home card.
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

/// True when the obligation has a charge that has not been deducted yet.
bool obligationNeedsAttention(RecurringExpense item, {DateTime? now}) {
  return item.enabled && item.dueDates(now ?? deviceNow(), max: 1).isNotEmpty;
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
    final palette = AppPalette.of(context);
    return _ObligationColors(
      accent: palette.accent,
      textPrimary: palette.textPrimary,
      textSecondary: palette.textSecondary,
      warning: AppColors.warningOf(context),
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
