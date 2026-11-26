// The alert rules of NotificationService. Each compares the ledger with
// the last snapshot and writes an alert when a value crossed a threshold,
// so reopening the app never repeats an alert. Event keys make every alert
// fire once (per period, goal or expense).
//
// Smart alerts (forecast, spending pace, goal deadline, period summary)
// also need SmartSettings.alerts and enough history behind them.

part of 'notification_service.dart';

/// One method per alert kind; each returns true when it added an alert.
extension _NotificationRules on NotificationService {
  /// Seeds snapshot from the store and pretends completed goals already notified.
  void _applyBaseline(TransactionStore store) {
    _snapshot = _NotificationSnapshot.fromStore(store);

    for (final goal in store.goals) {
      if (!goal.isCompleted) continue;
      _eventKeys.add(_goalReachedKey(goal.id));
      for (final percent in NotificationThresholds.goalPercents) {
        _eventKeys.add(_goalProgressKey(goal.id, percent));
      }
    }
  }

  void _refreshSnapshot(TransactionStore store) {
    _snapshot = _NotificationSnapshot.fromStore(store);
  }

  /// Fires when the remaining balance drops through a
  /// [NotificationThresholds.remainingPercents] level, once per cycle.
  bool _evaluateBalance(TransactionStore store) {
    if (store.maxBalance <= 0) return false;

    final current = store.remainingRatio;
    final previous = _snapshot.remainingRatio;
    if (previous == null) return false;

    final crossed = <int>[];
    for (final percent in NotificationThresholds.remainingPercents) {
      final threshold = percent / 100;
      if (previous > threshold && current <= threshold) {
        crossed.add(percent);
      }
    }
    if (crossed.isEmpty) return false;

    final percent = crossed.reduce((a, b) => a < b ? a : b);
    final cycle = _incomeCycle(store);
    final left = '${formatMoney(store.balance)} $currencyLabel';
    final income = '${formatMoney(store.maxBalance)} $currencyLabel';
    return _tryAdd(
      type: NotificationType.balanceWarning,
      title: percent <= 10 ? 'رصيدك على وشك النفاد' : 'بقي ربع رصيد الفترة',
      message: percent <= 10
          ? 'بقي $left فقط من أصل $income.'
          : 'المتاح الآن $left من أصل $income. راقب مصروفاتك حتى الدخل القادم.',
      eventKey: 'balanceWarning:$percent:$cycle',
      metadata: {'percent': '$percent', 'cycle': cycle},
    );
  }

  /// Smart alert: at the recent pace the balance runs out before the next
  /// income. At most once a week per cycle, and only with enough history.
  bool _evaluateForecast(TransactionStore store) {
    if (!SmartSettings.instance.alerts || store.balance <= 0) return false;
    final facts = _factsFor(store);
    final untilIncome = facts.daysUntilIncome;
    final runway = facts.runwayDays;
    if (untilIncome == null || untilIncome < 3 || runway == null) return false;
    if (facts.weeksOfHistory < 1 || facts.loggedLast30 < 5) return false;
    final gap = (untilIncome - runway).ceil();
    if (gap < 2) return false;

    final dailyLimit = store.balance / untilIncome;
    final cycle = _incomeCycle(store);
    final week = CalendarPeriod.weeklyKey(facts.now);
    return _tryAdd(
      type: NotificationType.balanceWarning,
      title: 'قد ينفد رصيدك قبل الدخل',
      message:
          'بوتيرة آخر أسبوعين ينفد رصيدك قبل الدخل القادم بنحو '
          '${Ar.days.of(gap)}. حدّك اليومي الآمن '
          '${formatMoney(dailyLimit)} $currencyLabel.',
      eventKey: 'balanceForecast:$cycle:$week',
      metadata: {'cycle': cycle, 'gapDays': '$gap'},
    );
  }

  /// Fires when cycle spending climbs through a
  /// [NotificationThresholds.spendingPercents] share of the cycle's 100%.
  bool _evaluateSpending(TransactionStore store) {
    if (store.maxBalance <= 0) return false;

    final current = store.cycleSpent / store.maxBalance;
    final previous = _snapshot.spentRatio;
    if (previous == null) return false;

    final crossed = <int>[];
    for (final percent in NotificationThresholds.spendingPercents) {
      final threshold = percent / 100;
      if (previous < threshold && current >= threshold) {
        crossed.add(percent);
      }
    }
    if (crossed.isEmpty) return false;

    final percent = crossed.reduce((a, b) => a > b ? a : b);
    final cycle = _incomeCycle(store);
    return _tryAdd(
      type: NotificationType.highSpending,
      title: percent == 50
          ? 'صرفت نصف رصيد الفترة'
          : 'صرفت \u2066$percent%\u2069 من رصيد الفترة',
      message:
          'صرفت ${formatMoney(store.cycleSpent)} $currencyLabel من أصل '
          '${formatMoney(store.maxBalance)} $currencyLabel، '
          'والمتاح الآن ${formatMoney(store.balance)} $currencyLabel.',
      eventKey: 'highSpending:$percent:$cycle',
      metadata: {'percent': '$percent', 'cycle': cycle},
    );
  }

  /// Goal reached at 100%, or progress through a
  /// [NotificationThresholds.goalPercents] level.
  bool _evaluateGoals(TransactionStore store) {
    var changed = false;

    for (final goal in store.goals) {
      final current = store.goalRatio(goal);
      final previous = _snapshot.goalRatios[goal.id];

      if (goal.isCompleted) {
        changed |= _tryAdd(
          type: NotificationType.goalReached,
          title: 'اكتمل هدف ${Ar.quote(goal.name)}',
          message:
              'جمعت المبلغ المطلوب كاملاً: ${formatMoney(goal.targetAmount)} '
              '${currencyLabelFor(goal.currencyCode)}.',
          eventKey: _goalReachedKey(goal.id),
          relatedId: goal.id,
          metadata: {'goalName': goal.name, 'percent': '100'},
          createdAt: goal.completedAt,
        );
        continue;
      }

      if (previous == null) continue;

      final crossed = <int>[];
      for (final percent in NotificationThresholds.goalPercents) {
        final threshold = percent / 100;
        if (previous < threshold && current >= threshold) {
          crossed.add(percent);
        }
      }
      if (crossed.isEmpty) continue;

      final percent = crossed.reduce((a, b) => a > b ? a : b);
      final symbol = currencyLabelFor(goal.currencyCode);
      changed |= _tryAdd(
        type: NotificationType.goalProgress,
        title: 'وصل هدف ${Ar.quote(goal.name)} إلى \u2066$percent%\u2069',
        message:
            'وفّرت ${formatMoney(store.currentSaved(goal))} $symbol من أصل '
            '${formatMoney(goal.targetAmount)} $symbol.',
        eventKey: _goalProgressKey(goal.id, percent),
        relatedId: goal.id,
        metadata: {'goalName': goal.name, 'percent': '$percent'},
      );
    }

    return changed;
  }

  /// Notifies for new period-leftover or goal-periodic savings transfers.
  bool _evaluateTransfers(TransactionStore store) {
    var changed = false;

    for (final item in store.savingsTransfers) {
      if (!item.isSavingsIn) continue;
      if (_snapshot.knownTransactionIds.contains(item.id)) continue;

      final kind = item.transferKind;
      if (kind != SavingsTransferKind.periodLeftover &&
          kind != SavingsTransferKind.goalPeriodic) {
        continue;
      }

      final periodLabel = _periodAdjective(item);
      final goalName = _goalName(store, item.goalId);
      final amount =
          '${formatMoney(item.amount)} ${currencyLabelFor(item.currencyCode)}';
      final weekly = periodLabel == 'الأسبوعية';

      changed |= _tryAdd(
        type: NotificationType.savingsTransferred,
        title: 'أُضيف $amount إلى التوفير',
        message: kind == SavingsTransferKind.goalPeriodic
            ? 'الدفعة الدورية${goalName == null ? '' : ' لهدف $goalName'}.'
            : 'المتبقي من دخل ${weekly ? 'الأسبوع' : 'الشهر'} الماضي'
                  '${goalName == null ? '' : '، ضمن هدف $goalName'}.',
        eventKey: 'savingsTransfer:${item.id}',
        relatedId: item.id,
        metadata: {
          'amount': '${item.amount}',
          'periodType': kind == SavingsTransferKind.goalPeriodic
              ? 'goalPeriodic'
              : (item.processedPeriodKey?.startsWith('w:') == true
                    ? 'weekly'
                    : 'monthly'),
          'periodKey': ?item.processedPeriodKey,
          'goalName': ?goalName,
        },
        createdAt: item.dateTime,
      );
    }

    return changed;
  }

  /// Period-completed alerts when leftover was processed without a transfer row.
  bool _evaluatePeriods(TransactionStore store) {
    var changed = false;

    for (final token in store.processedPeriodTokens) {
      if (!token.startsWith('leftover:')) continue;
      if (_snapshot.knownProcessedTokens.contains(token)) continue;

      final periodKey = token.substring('leftover:'.length);
      if (periodKey.isEmpty) continue;

      final alreadyTransferred = _items.any(
        (item) =>
            item.type == NotificationType.savingsTransferred &&
            item.metadata['periodKey'] == periodKey,
      );
      if (alreadyTransferred) continue;

      final hasTransfer = store.savingsTransfers.any(
        (item) =>
            item.isSavingsIn &&
            item.transferKind == SavingsTransferKind.periodLeftover &&
            item.processedPeriodKey == periodKey,
      );
      if (hasTransfer) continue;

      final weekly = periodKey.contains('w:');
      final span = weekly ? 'الأسبوع' : 'الشهر';
      changed |= _tryAdd(
        type: NotificationType.recurringPeriodCompleted,
        title: 'انتهى $span دون توفير',
        message: 'لم يتبقَّ من دخل $span الماضي مبلغ يُنقل إلى التوفير.',
        eventKey: 'periodCompleted:$periodKey',
        relatedId: periodKey,
        metadata: {
          'periodKey': periodKey,
          'periodType': weekly ? 'weekly' : 'monthly',
        },
      );
    }

    return changed;
  }

  /// Flags a new, recent expense at least twice the average of the same
  /// category over the previous 90 days (five earlier expenses needed).
  /// Scheduled bills are expected amounts and have their own notices.
  bool _evaluateLargeExpenses(TransactionStore store) {
    final now = deviceNow();
    final recentFrom = now.subtract(
      const Duration(days: NotificationThresholds.largeExpenseRecentDays),
    );
    final fresh = [
      for (final expense in store.expenses)
        if (!_snapshot.knownTransactionIds.contains(expense.id) &&
            !expense.dateTime.isBefore(recentFrom) &&
            !RecurringExpense.isRecurringSource(expense.sourceId))
          expense,
    ];
    if (fresh.isEmpty) return false;

    var changed = false;
    for (final expense in fresh) {
      final category = expense.category ?? fallbackCategory.label;
      final from = expense.dateTime.subtract(
        const Duration(days: NotificationThresholds.largeExpenseWindowDays),
      );
      var count = 0;
      var sum = 0.0;
      for (final other in store.expenses) {
        if (identical(other, expense) || other.id == expense.id) continue;
        if ((other.category ?? fallbackCategory.label) != category) continue;
        if (other.dateTime.isBefore(from) ||
            !other.dateTime.isBefore(expense.dateTime)) {
          continue;
        }
        count++;
        sum += other.amount;
      }
      if (count < NotificationThresholds.minExpensesForLarge) continue;
      final average = sum / count;
      if (average <= 0 ||
          expense.amount <
              average * NotificationThresholds.largeExpenseMultiplier) {
        continue;
      }

      final symbol = currencyLabelFor(expense.currencyCode);
      final name = Ar.category(categoryFor(category).label);
      changed |= _tryAdd(
        type: NotificationType.largeExpense,
        title: 'مصروف أكبر من المعتاد على $name',
        message:
            '${formatMoney(expense.amount)} $symbol، أي أكثر من ضعف متوسط '
            'مصروفك على $name في آخر 90 يوماً '
            '(${formatMoney(average)} $symbol).',
        eventKey: 'largeExpense:${expense.id}',
        relatedId: expense.id,
        metadata: {'amount': '${expense.amount}', 'category': category},
        createdAt: expense.dateTime,
      );
    }
    return changed;
  }

  /// Smart alert: spending well ahead of the period. Once the period is a
  /// fifth gone (and five days old), spending a quarter more of its income
  /// than the share of time passed is flagged once per period, unless the
  /// balance forecast already warned about this period.
  bool _evaluateSpendingPace(TransactionStore store) {
    if (!SmartSettings.instance.alerts || store.maxBalance <= 0) return false;
    final code = CurrencyStore.instance.activeCode;
    final start = store.cycleStartFor(code);
    final end = _cycleEnd(store, start);
    if (start == null || end == null) return false;
    final now = deviceNow();
    final spentShare = store.cycleSpent / store.maxBalance;
    if (!isSpendingAhead(
      start: start,
      end: end,
      now: now,
      spentShare: spentShare,
    )) {
      return false;
    }
    final length = end.difference(start).inHours / 24;
    final passed = now.difference(start).inHours / 24;
    final elapsed = passed / length;
    final cycle = _incomeCycle(store);
    if (_eventKeys.any((key) => key.startsWith('balanceForecast:$cycle'))) {
      return false;
    }
    final daysLeft = (length - passed).ceil();
    return _tryAdd(
      type: NotificationType.highSpending,
      title: 'صرفك يسبق الفترة',
      message:
          'صرفت \u2066${(spentShare * 100).round()}%\u2069 من رصيد الفترة ولم '
          'يمضِ منها إلا \u2066${(elapsed * 100).round()}%\u2069. '
          'بقي من رصيدك ${formatMoney(store.balance)} $currencyLabel، '
          'وأمامك نحو ${Ar.days.of(daysLeft)} حتى نهايتها.',
      eventKey: 'spendingPace:$cycle',
      metadata: {'kind': 'pace', 'cycle': cycle},
    );
  }

  /// Smart alert: an unfinished goal whose deadline is a week away or less,
  /// once per goal.
  bool _evaluateGoalDeadlines(TransactionStore store) {
    if (!SmartSettings.instance.alerts) return false;
    final today = deviceNow();
    var changed = false;
    for (final goal in store.activeGoals) {
      final saved = store.goalProgress(goal);
      final remaining = goal.targetAmount - saved;
      if (remaining <= 0) continue;
      final months = SmartFactsLoader.plannedMonths(goal.duration);
      final deadline = goal.createdAt.add(
        Duration(days: (months * 30).round()),
      );
      final daysLeft = calendarDaysBetween(today, deadline);
      if (daysLeft < 1 || daysLeft > NotificationThresholds.goalDeadlineDays) {
        continue;
      }
      final symbol = currencyLabelFor(goal.currencyCode);
      changed |= _tryAdd(
        type: NotificationType.goalProgress,
        title: 'موعد هدف ${Ar.quote(goal.name)} بعد ${Ar.days.of(daysLeft)}',
        message:
            'ينقصه ${formatMoney(remaining)} $symbol، أي نحو '
            '${formatMoney(remaining / daysLeft)} $symbol يومياً حتى موعده.',
        eventKey: 'goalDeadline:${goal.id}',
        relatedId: goal.id,
        metadata: {'goalName': goal.name, 'kind': 'deadline'},
      );
    }
    return changed;
  }

  /// Smart alert: when a balance period ends (a new one started), a short
  /// summary of the one that ended: spent, its income, and the biggest
  /// category. Periods under five days or without spending are skipped.
  bool _evaluateCycleSummary(TransactionStore store) {
    if (!SmartSettings.instance.alerts) return false;
    final previousKey = _snapshot.cycleKey;
    final previousStart = _snapshot.cycleStart;
    final code = CurrencyStore.instance.activeCode;
    final start = store.cycleStartFor(code);
    if (previousKey == null || previousStart == null || start == null) {
      return false;
    }
    if (_snapshot.cycleCurrency != code) return false;
    if (store.cycleKey == previousKey || !start.isAfter(previousStart)) {
      return false;
    }
    if (start.difference(previousStart).inDays < 5) return false;

    var spent = 0.0;
    var income = 0.0;
    final totals = <String, double>{};
    for (final item in store.transactions) {
      if (item.currencyCode != code) continue;
      if (item.dateTime.isBefore(previousStart) ||
          !item.dateTime.isBefore(start)) {
        continue;
      }
      if (item.isExpense) {
        spent += item.amount;
        final category = item.category ?? fallbackCategory.label;
        totals[category] = (totals[category] ?? 0) + item.amount;
      } else if (item.isIncome) {
        income += item.amount;
      }
    }
    if (spent <= 0) return false;
    final top = largestCategory(totals)!;
    final share = (top.value / spent * 100).round();
    final ofIncome = income > 0
        ? ' من دخل قدره ${formatMoney(income)} $currencyLabel'
        : '';
    return _tryAdd(
      type: NotificationType.recurringPeriodCompleted,
      title: 'ملخّص الفترة الماضية',
      message:
          'صرفت ${formatMoney(spent)} $currencyLabel$ofIncome. '
          'أكبر بند كان ${Ar.category(top.key)} '
          '(\u2066$share%\u2069).',
      eventKey: 'cycleSummary:$code:$previousKey',
      metadata: {'kind': 'cycleSummary', 'periodKey': previousKey},
    );
  }

  /// Keeps the "nothing logged for three days" reminder in step with the
  /// newest expense; it is a scheduled device reminder, not a list item.
  void _syncLoggingNudge(TransactionStore store) {
    DateTime? last;
    for (final expense in store.expenses) {
      if (last == null || expense.dateTime.isAfter(last)) {
        last = expense.dateTime;
      }
    }
    if (last == _nudgeBase && _nudgeEnabled == _nudgeWanted) return;
    _nudgeBase = last;
    _nudgeEnabled = _nudgeWanted;
    unawaited(
      SystemNotifications.instance.syncLoggingNudge(
        enabled: _nudgeWanted,
        lastExpenseAt: last,
      ),
    );
  }

  bool get _nudgeWanted => SmartSettings.instance.alerts && !_muted;

  /// The facts the smart alerts read, for the active currency.
  SmartFacts _factsFor(TransactionStore store) => SmartFacts(
    now: deviceNow(),
    currencySymbol: currencyLabel,
    expenses: store.expenses,
    incomes: store.incomes,
    savingsTransfers: const [],
    balance: store.balance,
    monthlyIncome: store.configuredMonthlyIncome,
    incomeFrequency: store.preferredIncomeFrequency,
    hasRecurringIncome: store.hasRecurringIncome,
    savingsBalance: 0,
    goals: const [],
    completedGoals: 0,
    obligations: const [],
    pendingShopping: 0,
    streakCount: 0,
    usageStartedAt: null,
  );

  /// When the current period ends: the next income period for a weekly or
  /// monthly income, else null (no expected end to pace against).
  DateTime? _cycleEnd(TransactionStore store, DateTime? start) {
    if (start == null) return null;
    final frequency = store.preferredIncomeFrequency;
    if (!store.hasRecurringIncome || frequency == RecurringFrequency.none) {
      return null;
    }
    return CalendarPeriod.ofFrequency(frequency, deviceNow()).end;
  }

  String _incomeCycle(TransactionStore store) => 'cycle:${store.cycleKey}';

  String _goalReachedKey(String goalId) => 'goalReached:$goalId';

  String _goalProgressKey(String goalId, int percent) =>
      'goalProgress:$goalId:$percent';

  String? _goalName(TransactionStore store, String? goalId) {
    if (goalId == null) return null;
    for (final goal in store.goals) {
      if (goal.id == goalId) return goal.name;
    }
    return null;
  }

  /// Arabic weekly/monthly adjective from period key or recurring frequency.
  String? _periodAdjective(WaffrTransaction item) {
    final key = item.processedPeriodKey;
    if (key != null) {
      if (key.startsWith('w:')) return 'الأسبوعية';
      if (key.startsWith('m:')) return 'الشهرية';
    }
    return switch (item.frequency) {
      RecurringFrequency.weekly => 'الأسبوعية',
      RecurringFrequency.monthly => 'الشهرية',
      RecurringFrequency.none => null,
    };
  }
}
