// Converts app models to/from the JSON shapes expected by FastAPI /sync.

import 'dart:convert';

import 'package:waffer/data/models/app_notification.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/models/recurring_expense.dart';
import 'package:waffer/data/models/savings_goal.dart';
import 'package:waffer/data/models/transaction.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

const String defaultShoppingListId = 'shopping_default';
const String defaultShoppingListName = 'المشتريات';

double? parseMoney(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

// Wrap upserts + delete tombstones the way the /sync API expects per collection.
Map<String, dynamic> collectionPayload({
  required List<Map<String, dynamic>> upserts,
  required List<SyncTombstone> deletes,
}) {
  return {
    'upserts': upserts,
    'deletes': deletes.map((item) => item.toJson()).toList(),
  };
}

Map<String, dynamic> transactionToSync(WafferTransaction item) {
  return {
    'client_id': item.id,
    'type': item.isIncome ? 'income' : 'expense',
    'amount': item.amount.toString(),
    'category': item.category,
    'payment_method': item.paymentMethod,
    'note': item.note,
    'source_id': item.sourceId,
    'occurred_at': toSyncIso(item.dateTime),
    'frequency': item.frequency.name,
    'period_key': item.periodKey,
    'currency_code': item.currencyCode,
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

Map<String, dynamic> transferToSync(WafferTransaction item) {
  return {
    'client_id': item.id,
    'goal_client_id': item.goalId,
    'amount': item.amount.toString(),
    'direction': item.isSavingsOut ? 'to_balance' : 'to_savings',
    'kind': item.transferKind?.name,
    'note': item.note,
    'occurred_at': toSyncIso(item.dateTime),
    'processed_period_key': item.processedPeriodKey,
    'currency_code': item.currencyCode,
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

Map<String, dynamic> goalToSync(SavingsGoal item) {
  return {
    'client_id': item.id,
    'name': item.name,
    'target_amount': item.targetAmount.toString(),
    'duration': item.duration.name,
    'deadline': null,
    'allocate_percent': item.allocatePercent?.toString(),
    'allocate_amount': item.allocateAmount?.toString(),
    'deduct_frequency': item.deductFrequency.name,
    'is_periodic': item.isPeriodic,
    'duration_count': item.durationCount,
    'priority': item.priority,
    'completed_at': item.completedAt == null ? null : toSyncIso(item.completedAt),
    'completed_amount': item.completedAmount?.toString(),
    'created_at': toSyncIso(item.createdAt),
    'currency_code': item.currencyCode,
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

Map<String, dynamic> shoppingListToSync() {
  return {
    'client_id': defaultShoppingListId,
    'name': defaultShoppingListName,
    'updated_at': toSyncIso(syncNow()),
  };
}

Map<String, dynamic> recurringToSync(RecurringExpense item) {
  return {
    'client_id': item.id,
    'amount': item.amount.toString(),
    'category': item.category,
    'payment_method': item.paymentMethod,
    'note': item.note,
    'unit': item.unit.name,
    'interval_count': item.intervalCount,
    'next_due_at': toSyncIso(item.nextDueAt),
    'enabled': item.enabled,
    'requires_confirmation': item.requiresConfirmation,
    'remind_at': item.remindAt == null ? null : toSyncIso(item.remindAt!),
    'remind_on_income': item.remindOnIncome,
    'created_at': toSyncIso(item.createdAt),
    'currency_code': item.currencyCode,
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

Map<String, dynamic> notificationToSync(AppNotification item) {
  return {
    'client_id': item.id,
    'type': item.type.name,
    'title': item.title,
    'message': item.message,
    'event_key': item.eventKey,
    'related_id': item.relatedId,
    'metadata': item.metadata,
    'is_read': item.isRead,
    'created_at': toSyncIso(item.createdAt),
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

Map<String, dynamic> categoryToSync(CustomCategoryEntry item) {
  return {
    'client_id': item.id,
    'label': item.label,
    'icon_index': item.iconIndex,
    'updated_at': toSyncIso(item.syncUpdatedAt),
  };
}

WafferTransaction? transactionFromSync(Map<String, dynamic> raw) {
  final amount = parseMoney(raw['amount']);
  if (amount == null || amount <= 0) return null;
  final id = raw['client_id']?.toString().trim() ?? '';
  if (id.isEmpty) return null;

  final typeRaw = raw['type']?.toString();
  final type = typeRaw == 'income'
      ? TransactionType.income
      : TransactionType.expense;
  final occurred = parseEventLocal(raw['occurred_at'] ?? raw['dateTime']);
  if (occurred == null) return null;

  return WafferTransaction(
    id: id,
    type: type,
    amount: amount,
    category: _text(raw['category']),
    paymentMethod: _text(raw['payment_method'] ?? raw['paymentMethod']),
    note: _text(raw['note']),
    sourceId: _text(raw['source_id'] ?? raw['sourceId']),
    dateTime: occurred,
    currencyCode: Currencies.normalize(
      _text(raw['currency_code']) ?? _text(raw['currencyCode']),
    ),
    frequency: WafferTransaction.frequencyFrom(
      raw['frequency']?.toString(),
    ),
    periodKey: _text(raw['period_key'] ?? raw['periodKey']),
    updatedAt: parseSyncDate(raw['updated_at'] ?? raw['updatedAt']),
  );
}

WafferTransaction? transferFromSync(Map<String, dynamic> raw) {
  final amount = parseMoney(raw['amount']);
  if (amount == null || amount <= 0) return null;
  final id = raw['client_id']?.toString().trim() ?? '';
  if (id.isEmpty) return null;

  final direction = raw['direction']?.toString();
  final kind = WafferTransaction.transferKindFrom(raw['kind']?.toString());
  final outgoing = direction == 'to_balance' ||
      kind == SavingsTransferKind.withdraw;
  final occurred = parseEventLocal(raw['occurred_at'] ?? raw['dateTime']);
  if (occurred == null) return null;

  return WafferTransaction(
    id: id,
    type: outgoing ? TransactionType.savingsOut : TransactionType.savingsIn,
    amount: amount,
    note: _text(raw['note']),
    dateTime: occurred,
    currencyCode: Currencies.normalize(
      _text(raw['currency_code']) ?? _text(raw['currencyCode']),
    ),
    transferKind: kind ??
        (outgoing
            ? SavingsTransferKind.withdraw
            : SavingsTransferKind.manual),
    goalId: _text(raw['goal_client_id'] ?? raw['goalId']),
    processedPeriodKey: _text(
      raw['processed_period_key'] ?? raw['processedPeriodKey'],
    ),
    updatedAt: parseSyncDate(raw['updated_at'] ?? raw['updatedAt']),
  );
}

SavingsGoal? goalFromSync(Map<String, dynamic> raw) {
  return SavingsGoal.decode(
    jsonEncode({
      'id': raw['client_id'] ?? raw['id'],
      'name': raw['name'],
      'targetAmount': parseMoney(raw['target_amount'] ?? raw['targetAmount']),
      'currencyCode': raw['currency_code'] ?? raw['currencyCode'],
      'createdAt': raw['created_at'] ?? raw['createdAt'],
      'completedAt': raw['completed_at'] ?? raw['completedAt'],
      'completedAmount':
          parseMoney(raw['completed_amount'] ?? raw['completedAmount']),
      'duration': raw['duration'],
      'allocatePercent':
          parseMoney(raw['allocate_percent'] ?? raw['allocatePercent']),
      'allocateAmount':
          parseMoney(raw['allocate_amount'] ?? raw['allocateAmount']),
      'deductFrequency':
          raw['deduct_frequency'] ?? raw['deductFrequency'],
      'isPeriodic': raw['is_periodic'] ?? raw['isPeriodic'],
      'durationCount': raw['duration_count'] ?? raw['durationCount'],
      'priority': raw['priority'],
      'updatedAt': raw['updated_at'] ?? raw['updatedAt'],
    }),
  );
}

RecurringExpense? recurringFromSync(Map<String, dynamic> raw) {
  return RecurringExpense.decode(
    jsonEncode({
      'id': raw['client_id'] ?? raw['id'],
      'amount': parseMoney(raw['amount']),
      'currencyCode': raw['currency_code'] ?? raw['currencyCode'],
      'category': raw['category'],
      'paymentMethod': raw['payment_method'] ?? raw['paymentMethod'],
      'note': raw['note'],
      'unit': raw['unit'],
      'intervalCount': raw['interval_count'] ?? raw['intervalCount'],
      'createdAt': raw['created_at'] ?? raw['createdAt'],
      'nextDueAt': raw['next_due_at'] ?? raw['nextDueAt'],
      'enabled': raw['enabled'],
      'requiresConfirmation':
          raw['requires_confirmation'] ?? raw['requiresConfirmation'],
      'remindAt': raw['remind_at'] ?? raw['remindAt'],
      'remindOnIncome': raw['remind_on_income'] ?? raw['remindOnIncome'],
      'updatedAt': raw['updated_at'] ?? raw['updatedAt'],
    }),
  );
}

AppNotification? notificationFromSync(Map<String, dynamic> raw) {
  return AppNotification.decode(
    jsonEncode({
      'id': raw['client_id'] ?? raw['id'],
      'type': raw['type'],
      'title': raw['title'],
      'message': raw['message'],
      'createdAt': raw['created_at'] ?? raw['createdAt'],
      'isRead': raw['is_read'] ?? raw['isRead'],
      'eventKey': raw['event_key'] ?? raw['eventKey'],
      'relatedId': raw['related_id'] ?? raw['relatedId'],
      'metadata': raw['metadata'],
      'updatedAt': raw['updated_at'] ?? raw['updatedAt'],
    }),
  );
}

CustomCategoryEntry? categoryFromSync(Map<String, dynamic> raw) {
  return CustomCategoryEntry.fromSync(raw);
}

List<Map<String, dynamic>> asMapList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic>)
        item
      else if (item is Map)
        Map<String, dynamic>.from(item),
  ];
}

List<SyncTombstone> tombstonesFromSync(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (SyncTombstone.decode(item) != null) SyncTombstone.decode(item)!,
  ];
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
