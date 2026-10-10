// AI insights and expense categories, behind the user's opt-in.
//
// Both features are off until turned on in the AI permissions screen.
// Insights are cached per currency and period, so the home card and the
// reports summary normally cost one request per day.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:waffr/core/ai/ai_client.dart';
import 'package:waffr/core/ai/spending_summary.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/data/models/ai_insights.dart';
import 'package:waffr/data/models/calendar_period.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

class AiInsightsService extends ChangeNotifier {
  AiInsightsService._();

  static final AiInsightsService instance = AiInsightsService._();

  static const String insightsEnabledKey = 'ai_insights_enabled';
  static const String categorizeEnabledKey = 'ai_categorize_enabled';
  static const String _cacheKey = 'ai_insights_cache';

  // Kept answers; older periods drop off first.
  static const int _cacheLimit = 8;

  // How long an answer stays fresh before a screen asks again.
  static const Map<AiInsightsKind, Duration> _freshFor = {
    AiInsightsKind.weekly: Duration(hours: 12),
    AiInsightsKind.monthly: Duration(hours: 24),
  };

  bool _insightsEnabled = false;
  bool _categorizeEnabled = false;
  final Map<String, AiInsights> _cache = {};
  final Set<String> _loading = {};
  final Map<String, AiFailure> _failures = {};
  final Map<String, String?> _categoryMemo = {};
  Future<void>? _loader;

  bool get insightsEnabled => _insightsEnabled;
  bool get categorizeEnabled => _categorizeEnabled;

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    _insightsEnabled = prefs.getBool(insightsEnabledKey) ?? false;
    _categorizeEnabled = prefs.getBool(categorizeEnabledKey) ?? false;
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = AiInsights.fromJson(entry.value);
            if (value != null) _cache[entry.key.toString()] = value;
          }
        }
      } on FormatException {
        // A damaged cache only costs a fresh request.
      }
    }
    notifyListeners();
  }

  Future<void> setInsightsEnabled(bool value) async {
    await ensureLoaded();
    _insightsEnabled = value;
    if (!value) {
      _cache.clear();
      _failures.clear();
      final prefs = await AppPrefs.instance;
      await prefs.remove(_cacheKey);
    }
    final prefs = await AppPrefs.instance;
    await prefs.setBool(insightsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setCategorizeEnabled(bool value) async {
    await ensureLoaded();
    _categorizeEnabled = value;
    _categoryMemo.clear();
    final prefs = await AppPrefs.instance;
    await prefs.setBool(categorizeEnabledKey, value);
    notifyListeners();
  }

  String _keyFor(AiInsightsKind kind) {
    final frequency = kind == AiInsightsKind.weekly
        ? RecurringFrequency.weekly
        : RecurringFrequency.monthly;
    final period = CalendarPeriod.keyFor(frequency, deviceNow());
    return '${kind.name}|${CurrencyStore.instance.activeCode}|$period';
  }

  /// Latest answer for [kind] in the active currency and current period.
  AiInsights? insightsFor(AiInsightsKind kind) => _cache[_keyFor(kind)];

  bool isLoading(AiInsightsKind kind) => _loading.contains(_keyFor(kind));

  AiFailure? failureFor(AiInsightsKind kind) => _failures[_keyFor(kind)];

  /// True when there is nothing yet to analyse for [kind].
  bool lacksData(AiInsightsKind kind) {
    final store = TransactionStore.instance;
    final since = CalendarPeriod.ofFrequency(
      kind == AiInsightsKind.weekly
          ? RecurringFrequency.weekly
          : RecurringFrequency.monthly,
      deviceNow(),
    ).start.subtract(const Duration(days: 31));
    return !store.expenses.any((item) => item.dateTime.isAfter(since));
  }

  /// Fetches [kind] unless a fresh answer is cached. [force] skips the cache.
  Future<void> refresh(AiInsightsKind kind, {bool force = false}) async {
    await ensureLoaded();
    if (!_insightsEnabled) return;
    final key = _keyFor(kind);
    if (_loading.contains(key)) return;

    final cached = _cache[key];
    final fresh = cached != null &&
        deviceNow().difference(cached.fetchedAt) < _freshFor[kind]!;
    if (fresh && !force) return;
    if (lacksData(kind)) return;

    _loading.add(key);
    _failures.remove(key);
    notifyListeners();
    try {
      final body = await _summary(kind);
      final json = await AiClient.instance.post('/ai/insights', body);
      final result = AiInsights.fromJson(json, fetchedAt: deviceNow());
      if (result == null) throw const AiException(AiFailure.unavailable);
      _cache[key] = result;
      await _persistCache();
    } on AiException catch (error) {
      _failures[key] = error.failure;
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  Future<Map<String, Object?>> _summary(AiInsightsKind kind) async {
    final store = TransactionStore.instance;
    final recurring = RecurringExpenseStore.instance;
    await store.ensureLoaded();
    await recurring.ensureLoaded();
    final code = CurrencyStore.instance.activeCode;
    final income = store.configuredMonthlyIncome ??
        store.referenceIncome(RecurringFrequency.monthly);

    return buildSpendingSummary(
      kind: kind,
      currencyCode: code,
      now: deviceNow(),
      expenses: store.expenses,
      balance: store.balance,
      cycleSpent: store.cycleSpent,
      maxBalance: store.maxBalance,
      monthlyIncome: income,
      incomeFrequency: store.preferredIncomeFrequency,
      hasRecurringIncome: store.hasRecurringIncome,
      totalSaved: store.savingsBalance,
      goals: [
        for (final goal in store.activeGoals)
          GoalTotal(
            name: goal.name,
            target: goal.targetAmount,
            saved: store.goalProgress(goal),
          ),
      ],
      obligations: recurring.itemsFor(code),
    );
  }

  Future<void> _persistCache() async {
    while (_cache.length > _cacheLimit) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.fetchedAt.isBefore(b.value.fetchedAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    final prefs = await AppPrefs.instance;
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        for (final entry in _cache.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  /// The category that fits [note], or null when off, unsure or offline.
  /// Only the note text and the category names are sent.
  Future<String?> suggestCategory(String note, List<String> categories) async {
    await ensureLoaded();
    final text = note.trim();
    if (!_categorizeEnabled || text.length < 2 || categories.isEmpty) {
      return null;
    }
    final memoKey = '$text|${categories.join(',')}';
    if (_categoryMemo.containsKey(memoKey)) return _categoryMemo[memoKey];

    try {
      final json = await AiClient.instance.post('/ai/categorize', {
        'note': text.length > 200 ? text.substring(0, 200) : text,
        'categories': categories.take(40).toList(),
      });
      final category = json['category']?.toString();
      final result = categories.contains(category) ? category : null;
      _categoryMemo[memoKey] = result;
      return result;
    } on AiException {
      return null;
    }
  }

  /// Forgets answers and opt-ins after a local data wipe; the next read
  /// reloads them from (now empty) prefs.
  void resetCache() {
    _insightsEnabled = false;
    _categorizeEnabled = false;
    _loader = null;
    _cache.clear();
    _failures.clear();
    _categoryMemo.clear();
    unawaited(
      AppPrefs.instance.then((prefs) => prefs.remove(_cacheKey)),
    );
    notifyListeners();
  }
}
