// Savings goal model, duration presets, and JSON encode/decode for prefs.

import 'dart:convert';

import 'package:waffr/data/models/currency.dart';
import 'package:waffr/data/models/transaction.dart';

// How long the user picked for the goal in the create dialog.
enum GoalDurationPreset { week, month, threeMonths, sixMonths, year }

extension GoalDurationPresetLabel on GoalDurationPreset {
  String get label => switch (this) {
    GoalDurationPreset.week => 'أسبوع',
    GoalDurationPreset.month => 'شهر',
    GoalDurationPreset.threeMonths => '3 أشهر',
    GoalDurationPreset.sixMonths => '6 أشهر',
    GoalDurationPreset.year => 'سنة',
  };

  // Maps a raw cycle count back to the closest preset for the UI.
  static GoalDurationPreset fromCount(
    int count, {
    RecurringFrequency frequency = RecurringFrequency.monthly,
  }) {
    if (frequency == RecurringFrequency.weekly) {
      if (count <= 1) return GoalDurationPreset.week;
      if (count <= 5) return GoalDurationPreset.month;
      if (count <= 16) return GoalDurationPreset.threeMonths;
      if (count <= 32) return GoalDurationPreset.sixMonths;
      return GoalDurationPreset.year;
    }
    if (count <= 1) return GoalDurationPreset.month;
    if (count <= 3) return GoalDurationPreset.threeMonths;
    if (count <= 6) return GoalDurationPreset.sixMonths;
    return GoalDurationPreset.year;
  }

  // Deduction cycles for this preset given weekly vs monthly income.
  int cycleCount(RecurringFrequency frequency) {
    return switch (this) {
      GoalDurationPreset.week => frequency == RecurringFrequency.weekly ? 1 : 1,
      GoalDurationPreset.month =>
        frequency == RecurringFrequency.weekly ? 4 : 1,
      GoalDurationPreset.threeMonths =>
        frequency == RecurringFrequency.weekly ? 13 : 3,
      GoalDurationPreset.sixMonths =>
        frequency == RecurringFrequency.weekly ? 26 : 6,
      GoalDurationPreset.year =>
        frequency == RecurringFrequency.weekly ? 52 : 12,
    };
  }
}

// One savings goal. Progress only counts transfers after [createdAt];
// lower [priority] sorts first in the list.
class SavingsGoal {
  final String id;
  final String name;
  final double targetAmount;
  final String currencyCode;
  final DateTime createdAt;
  final DateTime? completedAt;
  final double? completedAmount;
  final GoalDurationPreset duration;
  final double? allocatePercent;
  final double? allocateAmount;
  final RecurringFrequency deductFrequency;
  final bool isPeriodic;
  final int? durationCount;
  final int priority;
  final DateTime? updatedAt;

  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currencyCode = defaultCurrencyCode,
    required this.createdAt,
    required this.duration,
    this.completedAt,
    this.completedAmount,
    this.allocatePercent,
    this.allocateAmount,
    this.deductFrequency = RecurringFrequency.monthly,
    this.isPeriodic = false,
    this.durationCount,
    this.priority = 0,
    this.updatedAt,
  });

  DateTime get syncUpdatedAt => (updatedAt ?? createdAt).toUtc();

  // Prefer an explicit durationCount; otherwise derive from the preset.
  int cyclesFor(RecurringFrequency frequency) {
    if (durationCount != null && durationCount! > 0) return durationCount!;
    return duration.cycleCount(frequency);
  }

  bool get isCompleted => completedAt != null;

  // Copies fields; set [touch] to bump updatedAt for sync.
  SavingsGoal copyWith({
    DateTime? completedAt,
    double? completedAmount,
    double? allocatePercent,
    double? allocateAmount,
    RecurringFrequency? deductFrequency,
    bool? isPeriodic,
    int? durationCount,
    int? priority,
    DateTime? updatedAt,
    bool touch = false,
  }) {
    return SavingsGoal(
      id: id,
      name: name,
      targetAmount: targetAmount,
      currencyCode: currencyCode,
      createdAt: createdAt,
      duration: duration,
      completedAt: completedAt ?? this.completedAt,
      completedAmount: completedAmount ?? this.completedAmount,
      allocatePercent: allocatePercent ?? this.allocatePercent,
      allocateAmount: allocateAmount ?? this.allocateAmount,
      deductFrequency: deductFrequency ?? this.deductFrequency,
      isPeriodic: isPeriodic ?? this.isPeriodic,
      durationCount: durationCount ?? this.durationCount,
      priority: priority ?? this.priority,
      updatedAt: updatedAt ?? (touch ? DateTime.now().toUtc() : this.updatedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'targetAmount': targetAmount,
    'currencyCode': currencyCode,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'completedAmount': completedAmount,
    'duration': duration.name,
    'allocatePercent': allocatePercent,
    'allocateAmount': allocateAmount,
    'deductFrequency': deductFrequency.name,
    'isPeriodic': isPeriodic,
    'durationCount': durationCount,
    'priority': priority,
    'updatedAt': syncUpdatedAt.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  // Parses prefs JSON; returns null if name/target are missing or invalid.
  static SavingsGoal? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final target = (decoded['targetAmount'] as num?)?.toDouble() ?? 0;
      if (target <= 0) return null;

      final name = decoded['name']?.toString().trim() ?? '';
      if (name.isEmpty) return null;

      return SavingsGoal(
        id: decoded['id']?.toString() ?? newId(),
        name: name,
        targetAmount: target,
        currencyCode: Currencies.normalize(
          decoded['currencyCode']?.toString() ??
              decoded['currency_code']?.toString(),
        ),
        createdAt:
            (DateTime.tryParse(decoded['createdAt']?.toString() ?? '') ??
                    DateTime.now())
                .toLocal(),
        completedAt: DateTime.tryParse(decoded['completedAt']?.toString() ?? '')
            ?.toLocal(),
        completedAmount: (decoded['completedAmount'] as num?)?.toDouble(),
        duration: _parseDuration(decoded['duration']?.toString()),
        allocatePercent: (decoded['allocatePercent'] as num?)?.toDouble(),
        allocateAmount: (decoded['allocateAmount'] as num?)?.toDouble(),
        deductFrequency: _parseFrequency(
          decoded['deductFrequency']?.toString(),
          periodic: decoded['isPeriodic'] == true,
        ),
        isPeriodic: decoded['isPeriodic'] == true,
        durationCount: (decoded['durationCount'] as num?)?.toInt(),
        priority: (decoded['priority'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(decoded['updatedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static String newId() => 'g${DateTime.now().microsecondsSinceEpoch}';

  static GoalDurationPreset _parseDuration(String? raw) {
    return switch (raw) {
      'week' => GoalDurationPreset.week,
      'threeMonths' => GoalDurationPreset.threeMonths,
      'sixMonths' => GoalDurationPreset.sixMonths,
      'year' => GoalDurationPreset.year,
      _ => GoalDurationPreset.month,
    };
  }

  static RecurringFrequency _parseFrequency(
    String? raw, {
    bool periodic = false,
  }) {
    return switch (raw) {
      'weekly' => RecurringFrequency.weekly,
      'monthly' => RecurringFrequency.monthly,
      _ => periodic ? RecurringFrequency.monthly : RecurringFrequency.none,
    };
  }
}
