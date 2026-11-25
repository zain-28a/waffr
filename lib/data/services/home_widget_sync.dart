// Keeps the home screen widgets current. Text is formatted here, in
// Arabic and in the active currency, so the native widgets only display it.
// Native code: android/app/src/main/kotlin/com/waffr/app/widgets and
// ios/WaffrWidgets.
//
// The widgets are redrawn whenever the ledger changes (the only way their
// numbers change), and the Android widgets also every few hours on their
// own, so the parts that depend on the date (the month, "today", how far a
// bill is) are worked out natively from the dates saved here rather than
// from text written days earlier.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:waffr/core/insights/smart/arabic_text.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/usage/streak_math.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/utils/calendar_days.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/data/models/transaction.dart';

/// Writes the figures the home screen widgets show and asks them to redraw.
class HomeWidgetSync {
  HomeWidgetSync._();

  /// The app-wide service.
  static final HomeWidgetSync instance = HomeWidgetSync._();

  /// Shared with the iOS widget extension (App Groups capability).
  static const String appGroupId = 'group.com.waffr.app';

  static const List<({String android, String ios})> _widgets = [
    (
      android: 'com.waffr.app.widgets.BalanceWidgetProvider',
      ios: 'WaffrBalanceWidget',
    ),
    (
      android: 'com.waffr.app.widgets.QuickAddWidgetProvider',
      ios: 'WaffrQuickAddWidget',
    ),
    (
      android: 'com.waffr.app.widgets.GoalWidgetProvider',
      ios: 'WaffrGoalWidget',
    ),
    (
      android: 'com.waffr.app.widgets.ObligationWidgetProvider',
      ios: 'WaffrObligationWidget',
    ),
    (
      android: 'com.waffr.app.widgets.StreakWidgetProvider',
      ios: 'WaffrStreakWidget',
    ),
    (
      android: 'com.waffr.app.widgets.MonthWidgetProvider',
      ios: 'WaffrMonthWidget',
    ),
  ];

  /// Prefs key of the "hide amounts on the home screen" switch.
  static const String hideAmountsKey = 'widget_hide_amounts';

  /// Whether the widgets show dots instead of amounts.
  Future<bool> hideAmounts() async =>
      (await AppPrefs.instance).getBool(hideAmountsKey) ?? false;

  /// Turns the amount mask on or off and redraws the widgets.
  Future<void> setHideAmounts(bool hide) async {
    await (await AppPrefs.instance).setBool(hideAmountsKey, hide);
    await refresh();
  }

  bool _started = false;
  Timer? _debounce;

  /// True on Android and iOS, the platforms with widgets.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Starts following the stores; later changes refresh the widgets.
  Future<void> start() async {
    if (_started || !supported) return;
    _started = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(appGroupId);
      }
    } on PlatformException {
      // No widget extension configured yet; data still saves on Android.
    } on MissingPluginException {
      return;
    }
    for (final source in <Listenable>[
      TransactionStore.instance,
      RecurringExpenseStore.instance,
      CurrencyStore.instance,
      UsageStreakService.instance,
    ]) {
      source.addListener(_schedule);
    }
    await refresh();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), refresh);
  }

  /// Saves fresh widget data and redraws every widget; errors are ignored.
  Future<void> refresh() async {
    if (!supported) return;
    try {
      final data = await _snapshot();
      for (final entry in data.entries) {
        await HomeWidget.saveWidgetData<Object>(entry.key, entry.value);
      }
      for (final widget in _widgets) {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: widget.android,
          iOSName: widget.ios,
        );
      }
    } on PlatformException {
      // A widget kind that is not installed is not an error worth surfacing.
    } on MissingPluginException {
      // Tests and unsupported hosts.
    }
  }

  Future<Map<String, Object>> _snapshot() async {
    final store = TransactionStore.instance;
    final recurring = RecurringExpenseStore.instance;
    final streak = UsageStreakService.instance;
    await Future.wait([
      store.ensureLoaded(),
      recurring.ensureLoaded(),
      streak.ensureLoaded(),
    ]);
    final now = deviceNow();
    final monthStart = CalendarPeriod.monthStart(now);
    final month = store.spendingBreakdown(since: monthStart);
    final monthIncome = store.incomes
        .where((item) => !item.dateTime.isBefore(monthStart))
        .fold(0.0, (sum, item) => sum + item.amount);
    final recent = [...store.expenses, ...store.incomes]
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return buildHomeWidgetData(
      now: now,
      symbol: CurrencyStore.instance.activeSymbol,
      balance: store.balance,
      spent: store.cycleSpent,
      maxBalance: store.maxBalance,
      remainingRatio: store.remainingRatio,
      goal: store.activeGoals.isEmpty
          ? null
          : (
              name: store.activeGoals.first.name,
              target: store.activeGoals.first.targetAmount,
              saved: store.goalProgress(store.activeGoals.first),
            ),
      obligations: [
        for (final item in recurring.itemsFor(
          CurrencyStore.instance.activeCode,
        ))
          if (item.enabled)
            (
              name: item.note?.trim().isNotEmpty == true
                  ? item.note!.trim()
                  : item.category,
              amount: item.amount,
              due: item.nextDueAt,
            ),
      ],
      streak: streak.count,
      streakLastDay: streak.lastDay,
      hideAmounts: await hideAmounts(),
      monthSpent: month.total,
      monthIncome: monthIncome,
      monthTop: [
        for (final item in month.items.take(4))
          (category: item.category, amount: item.amount, share: item.share),
      ],
      recent: [for (final item in recent.take(4)) item],
    );
  }
}

/// The text every widget shows, keyed as the native widgets read it.
@visibleForTesting
Map<String, Object> buildHomeWidgetData({
  required DateTime now,
  required String symbol,
  required double balance,
  required double spent,
  required double maxBalance,
  required double remainingRatio,
  required ({String name, double target, double saved})? goal,
  required List<({String name, double amount, DateTime due})> obligations,
  required int streak,
  DateTime? streakLastDay,
  bool hideAmounts = false,
  double monthSpent = 0,
  double monthIncome = 0,
  List<({String category, double amount, double share})> monthTop = const [],
  List<WaffrTransaction> recent = const [],
}) {
  // Amounts become dots when the user hides them on the home screen;
  // shares and dates stay.
  String money(double value) => hideAmounts ? '••••' : formatMoney(value);
  String dayKey(DateTime value) => StreakSnapshot.dayKey(value)!;

  final remaining = (remainingRatio * 100).round().clamp(0, 100);
  final data = <String, Object>{
    'hide_amounts': hideAmounts,
    'balance_amount': money(balance),
    'balance_currency': symbol,
    'balance_percent': '$remaining',
    'balance_percent_label': 'المتبقي \u2066$remaining%\u2069',
    'balance_caption': 'مصروف ${money(spent)} من ${money(maxBalance)} $symbol',
    'cycle_spent': money(spent),
    'cycle_income': money(maxBalance),
  };

  // This month: totals and up to four categories with their colors. The
  // widget compares month_key with today and asks to open the app once the
  // month has turned.
  data['month_key'] = dayKey(now).substring(0, 7);
  data['month_label'] = CalendarPeriod.monthName(now.month);
  data['month_spent'] = money(monthSpent);
  data['month_income'] = money(monthIncome);
  data['month_top_count'] = monthTop.length;
  for (final (index, item) in monthTop.indexed) {
    final category = categoryFor(item.category);
    data['month_top_${index}_name'] = item.category;
    data['month_top_${index}_amount'] = money(item.amount);
    data['month_top_${index}_percent'] = '${(item.share * 100).round()}';
    data['month_top_${index}_color'] = category.color.toARGB32();
    data['month_top_${index}_color_dark'] = category.darkColor.toARGB32();
  }

  // The newest records for the large quick-add widget; the widget words
  // the day ("اليوم", "أمس", a date) from recent_N_day.
  data['recent_count'] = recent.length;
  for (final (index, item) in recent.indexed) {
    final income = item.isIncome;
    final category = income ? null : categoryFor(item.category);
    final note = item.note?.trim() ?? '';
    data['recent_${index}_title'] = note.isNotEmpty
        ? note
        : (income ? 'دخل' : category!.label);
    data['recent_${index}_amount'] =
        '${income ? '+' : '−'}${money(item.amount)}';
    data['recent_${index}_day'] = dayKey(item.dateTime);
    data['recent_${index}_income'] = income;
    data['recent_${index}_color'] = (category?.color ?? _incomeColor)
        .toARGB32();
    data['recent_${index}_color_dark'] =
        (category?.darkColor ?? _incomeDarkColor).toARGB32();
  }

  if (goal == null || goal.target <= 0) {
    data['goal_empty'] = true;
    data['goal_name'] = 'لا يوجد هدف بعد';
    data['goal_caption'] = 'اضغط لإنشاء هدفك الأول';
    data['goal_percent'] = '0';
    data['goal_percent_label'] = '';
  } else {
    final percent = (goal.saved / goal.target * 100).round().clamp(0, 100);
    data['goal_empty'] = false;
    data['goal_name'] = goal.name;
    data['goal_percent'] = '$percent';
    data['goal_percent_label'] = '\u2066$percent%\u2069';
    data['goal_caption'] =
        'تم توفير ${money(goal.saved)} من ${money(goal.target)} $symbol';
    data['goal_remaining'] =
        'المتبقي ${money(goal.target - goal.saved < 0 ? 0 : goal.target - goal.saved)} $symbol';
  }

  final today = DateTime(now.year, now.month, now.day);
  final upcoming = [...obligations]..sort((a, b) => a.due.compareTo(b.due));
  if (upcoming.isEmpty) {
    data['obligation_empty'] = true;
    data['obligation_name'] = 'لا توجد التزامات قادمة';
    data['obligation_amount'] = '';
    data['obligation_value'] = '';
    data['obligation_when'] = '';
  } else {
    final next = upcoming.first;
    final dueDay = DateTime(next.due.year, next.due.month, next.due.day);
    final days = calendarDaysBetween(today, dueDay);
    data['obligation_empty'] = false;
    data['obligation_name'] = next.name;
    data['obligation_amount'] = '${money(next.amount)} $symbol';
    data['obligation_value'] = money(next.amount);
    data['obligation_due_day'] = dayKey(dueDay);
    data['obligation_when'] = switch (days) {
      < 0 => 'مستحق الآن',
      0 => 'اليوم',
      1 => 'غداً',
      _ => 'بعد ${Ar.days.of(days)}',
    };
  }

  final count = streak < 1 ? 1 : streak;
  data['streak_count'] = '$count';
  // The widget is not redrawn by the app on days it stays closed, so it
  // checks this date itself: past it, a whole day was skipped and the
  // streak shows as broken.
  if (streakLastDay != null) {
    final aliveUntil = DateTime(
      streakLastDay.year,
      streakLastDay.month,
      streakLastDay.day + 1,
    );
    data['streak_alive_until'] = StreakSnapshot.dayKey(aliveUntil)!;
  }
  data['streak_reset_label'] = 'ابدأ من جديد';
  // The ring fills toward the next milestone, as on the profile card.
  final milestone = nextStreakMilestone(count);
  data['streak_next'] =
      'بقي ${Ar.days.of(milestone - count)} على ${Ar.consecutiveDays.of(milestone)}';
  data['streak_percent'] =
      '${(count / nextStreakMilestone(count) * 100).round().clamp(0, 100)}';
  data['streak_word'] = switch (count) {
    1 => 'يوم',
    <= 10 => 'أيام',
    _ => 'يوماً',
  };
  data['streak_label'] = switch (count) {
    1 => 'اليوم الأول',
    2 => 'يومان متتاليان',
    >= 3 && <= 10 => 'أيام متتالية',
    _ => 'يوماً متتالياً',
  };
  return data;
}

// The income dot in the recent list: the app's brand greens.
const Color _incomeColor = Color(0xFF254A23);
const Color _incomeDarkColor = Color(0xFF7BC17A);
