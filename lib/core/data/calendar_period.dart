import 'package:waffer/core/data/transaction.dart';

enum SavingsRange { week, month, threeMonths, sixMonths, year }

extension SavingsRangeLabel on SavingsRange {
  String get label => switch (this) {
        SavingsRange.week => 'أسبوع',
        SavingsRange.month => 'شهر',
        SavingsRange.threeMonths => '3 أشهر',
        SavingsRange.sixMonths => '6 أشهر',
        SavingsRange.year => 'سنة',
      };
}

class CalendarPeriod {
  final DateTime start;
  final DateTime end;

  const CalendarPeriod({required this.start, required this.end});

  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(end);

  bool get isComplete {
    final now = DateTime.now();
    return !now.isBefore(end);
  }

  String get key {
    if (end.difference(start).inDays == 7) {
      return weeklyKey(start);
    }
    if (start.day == 1 && end == DateTime(start.year, start.month + 1)) {
      return monthlyKey(start);
    }
    return '${_isoDay(start)}_${_isoDay(end)}';
  }

  /// الأسبوع يبدأ السبت، بنفس حساب ReportScreen.
  static DateTime weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final daysFromSaturday = (day.weekday + 1) % 7;
    return day.subtract(Duration(days: daysFromSaturday));
  }

  static DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

  static String weeklyKey(DateTime date) {
    final start = weekStart(date);
    return 'w:${_isoDay(start)}';
  }

  static String monthlyKey(DateTime date) {
    final start = monthStart(date);
    return 'm:${start.year}-${_two(start.month)}';
  }

  static String keyFor(RecurringFrequency frequency, DateTime date) {
    return switch (frequency) {
      RecurringFrequency.weekly => weeklyKey(date),
      RecurringFrequency.monthly => monthlyKey(date),
      RecurringFrequency.none => '',
    };
  }

  static CalendarPeriod? parseKey(String key) {
    if (key.startsWith('w:')) {
      final date = DateTime.tryParse(key.substring(2));
      if (date == null) return null;
      final start = weekStart(date);
      return CalendarPeriod(start: start, end: start.add(const Duration(days: 7)));
    }
    if (key.startsWith('m:')) {
      final parts = key.substring(2).split('-');
      if (parts.length < 2) return null;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) return null;
      final start = DateTime(year, month);
      return CalendarPeriod(
        start: start,
        end: DateTime(start.year, start.month + 1),
      );
    }
    return null;
  }

  static CalendarPeriod ofFrequency(RecurringFrequency frequency, DateTime date) {
    switch (frequency) {
      case RecurringFrequency.weekly:
        final start = weekStart(date);
        return CalendarPeriod(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      case RecurringFrequency.monthly:
        final start = monthStart(date);
        return CalendarPeriod(
          start: start,
          end: DateTime(start.year, start.month + 1),
        );
      case RecurringFrequency.none:
        final day = DateTime(date.year, date.month, date.day);
        return CalendarPeriod(
          start: day,
          end: day.add(const Duration(days: 1)),
        );
    }
  }

  static DateTime nextStart(RecurringFrequency frequency, DateTime start) {
    return switch (frequency) {
      RecurringFrequency.weekly => start.add(const Duration(days: 7)),
      RecurringFrequency.monthly => DateTime(start.year, start.month + 1),
      RecurringFrequency.none => start.add(const Duration(days: 1)),
    };
  }

  /// الفترات المكتملة بين [since] والآن، من الأقدم إلى الأحدث.
  static List<String> completedKeysSince(
    RecurringFrequency frequency,
    DateTime since,
    DateTime now, {
    int maxKeys = 120,
  }) {
    if (frequency == RecurringFrequency.none) return const [];

    final keys = <String>[];
    var cursor = ofFrequency(frequency, since).start;
    final currentStart = ofFrequency(frequency, now).start;

    while (cursor.isBefore(currentStart) && keys.length < maxKeys) {
      keys.add(keyFor(frequency, cursor));
      cursor = nextStart(frequency, cursor);
    }
    return keys;
  }

  static CalendarPeriod forRange(SavingsRange range, int offset, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    final today = DateTime(moment.year, moment.month, moment.day);
    late DateTime start;
    late DateTime end;

    switch (range) {
      case SavingsRange.week:
        start = weekStart(today).subtract(Duration(days: offset * 7));
        end = start.add(const Duration(days: 7));
      case SavingsRange.month:
        start = DateTime(moment.year, moment.month - offset);
        end = DateTime(start.year, start.month + 1);
      case SavingsRange.threeMonths:
        final quarterStartMonth = ((moment.month - 1) ~/ 3) * 3 + 1;
        start = DateTime(moment.year, quarterStartMonth - offset * 3);
        end = DateTime(start.year, start.month + 3);
      case SavingsRange.sixMonths:
        final halfStartMonth = moment.month <= 6 ? 1 : 7;
        start = DateTime(moment.year, halfStartMonth - offset * 6);
        end = DateTime(start.year, start.month + 6);
      case SavingsRange.year:
        start = DateTime(moment.year - offset);
        end = DateTime(start.year + 1);
    }

    return CalendarPeriod(start: start, end: end);
  }

  static String rangeLabel(SavingsRange range, CalendarPeriod period) {
    final lastDay = period.end.subtract(const Duration(days: 1));
    switch (range) {
      case SavingsRange.week:
        if (period.start.month == lastDay.month &&
            period.start.year == lastDay.year) {
          return '${period.start.day} – ${lastDay.day} '
              '${monthName(period.start.month)} ${period.start.year}';
        }
        return '${period.start.day} ${monthName(period.start.month)}'
            ' – ${lastDay.day} ${monthName(lastDay.month)} ${lastDay.year}';
      case SavingsRange.month:
        return '${monthName(period.start.month)} ${period.start.year}';
      case SavingsRange.threeMonths:
      case SavingsRange.sixMonths:
        if (period.start.year == lastDay.year) {
          return '${monthName(period.start.month)} – '
              '${monthName(lastDay.month)} ${lastDay.year}';
        }
        return '${monthName(period.start.month)} ${period.start.year} – '
            '${monthName(lastDay.month)} ${lastDay.year}';
      case SavingsRange.year:
        return period.start.year.toString();
    }
  }

  static String currentPeriodCaption(SavingsRange range) {
    return switch (range) {
      SavingsRange.week => 'هذا الأسبوع',
      SavingsRange.month => 'هذا الشهر',
      SavingsRange.threeMonths => 'هذه الأشهر الثلاثة',
      SavingsRange.sixMonths => 'هذه الأشهر الستة',
      SavingsRange.year => 'هذه السنة',
    };
  }

  static const List<String> monthNames = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  static String monthName(int month) => monthNames[month - 1];

  static String _isoDay(DateTime date) =>
      '${date.year}-${_two(date.month)}-${_two(date.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
