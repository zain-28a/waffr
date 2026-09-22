import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/expense_categories.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_mapper.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';

class ShoppingItem {
  final String id;
  final String name;
  final DateTime createdAt;
  final bool isPurchased;
  final DateTime? purchasedAt;
  final String? expenseId;
  final DateTime? updatedAt;

  const ShoppingItem({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isPurchased = false,
    this.purchasedAt,
    this.expenseId,
    this.updatedAt,
  });

  DateTime get syncUpdatedAt => (updatedAt ?? createdAt).toUtc();

  ShoppingItem copyWith({
    bool? isPurchased,
    DateTime? purchasedAt,
    String? expenseId,
    DateTime? updatedAt,
    bool clearPurchase = false,
    bool touch = true,
  }) {
    return ShoppingItem(
      id: id,
      name: name,
      createdAt: createdAt,
      isPurchased: clearPurchase ? false : (isPurchased ?? this.isPurchased),
      purchasedAt: clearPurchase ? null : (purchasedAt ?? this.purchasedAt),
      expenseId: clearPurchase ? null : (expenseId ?? this.expenseId),
      updatedAt: updatedAt ??
          (touch ? DateTime.now().toUtc() : this.updatedAt),
    );
  }

  Map<String, dynamic> toSyncJson() => {
    'client_id': id,
    'list_client_id': defaultShoppingListId,
    'name': name,
    'quantity': 1,
    'price': null,
    'is_purchased': isPurchased,
    'purchased_at': purchasedAt == null ? null : toSyncIso(purchasedAt),
    'expense_client_id': expenseId,
    'created_at': toSyncIso(createdAt),
    'updated_at': toSyncIso(syncUpdatedAt),
  };

  static ShoppingItem? fromSync(Map<String, dynamic> raw) {
    final id = raw['client_id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final createdAt = parseEventLocal(raw['created_at'] ?? raw['createdAt']);
    if (id.isEmpty || name.isEmpty || createdAt == null) return null;
    return ShoppingItem(
      id: id,
      name: name,
      createdAt: createdAt,
      isPurchased: raw['is_purchased'] == true || raw['isPurchased'] == true,
      purchasedAt: parseEventLocal(raw['purchased_at'] ?? raw['purchasedAt']),
      expenseId: (raw['expense_client_id'] ?? raw['expenseId'])?.toString(),
      updatedAt: parseSyncDate(raw['updated_at'] ?? raw['updatedAt']),
    );
  }

  String encode() => jsonEncode(<String, dynamic>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'isPurchased': isPurchased,
    'purchasedAt': purchasedAt?.toIso8601String(),
    'expenseId': expenseId,
    'updatedAt': syncUpdatedAt.toIso8601String(),
  });

  static ShoppingItem? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final id = decoded['id']?.toString().trim() ?? '';
      final name = decoded['name']?.toString().trim() ?? '';
      final createdAt = DateTime.tryParse(
        decoded['createdAt']?.toString() ?? '',
      );

      if (id.isEmpty || name.isEmpty || createdAt == null) {
        return null;
      }

      return ShoppingItem(
        id: id,
        name: name,
        createdAt: createdAt.toLocal(),
        isPurchased: decoded['isPurchased'] == true,
        purchasedAt: DateTime.tryParse(
          decoded['purchasedAt']?.toString() ?? '',
        )?.toLocal(),
        expenseId: decoded['expenseId']?.toString(),
        updatedAt: DateTime.tryParse(decoded['updatedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

/// مخزن قائمة المشتريات المحلية.
///
/// إنشاء المصروف نفسه يبقى من مسؤولية [TransactionStore] حتى ينعكس
/// تلقائياً على الرصيد والسجل وبقية شاشات التطبيق.
class ShoppingListStore extends ChangeNotifier {
  ShoppingListStore._();

  static final ShoppingListStore instance = ShoppingListStore._();

  static const String itemsKey = 'shopping_list_items';

  final List<ShoppingItem> _items = [];

  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<ShoppingItem> get items => List.unmodifiable(_items);

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> addItem(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    await ensureLoaded();

    _items.insert(
      0,
      ShoppingItem(id: _newId(), name: trimmed, createdAt: deviceNow()),
    );

    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    if (_items.isEmpty) return;

    await SyncTombstones.instance.addMany(
      SyncCollection.shoppingItems,
      _items.map((item) => item.id),
    );
    _items.clear();
    await _persist();
    notifyListeners();
  }

  Future<bool> completePurchase({
    required String itemId,
    required double amount,
    required String category,
  }) async {
    if (amount <= 0) return false;

    await ensureLoaded();

    final index = _items.indexWhere((item) => item.id == itemId);
    if (index < 0) return false;

    final item = _items[index];
    if (item.isPurchased) return true;

    final expense = await TransactionStore.instance.addExpense(
      amount: amount,
      category: category,
      paymentMethod: paymentMethods.first,
      note: item.name,
      sourceId: 'shopping:$itemId',
    );

    if (expense == null) return false;

    final latestIndex = _items.indexWhere((entry) => entry.id == itemId);
    if (latestIndex < 0) return false;

    final latest = _items[latestIndex];
    _items[latestIndex] = latest.copyWith(
      isPurchased: true,
      purchasedAt: deviceNow(),
      expenseId: expense.id,
    );

    await _persist();
    notifyListeners();

    return true;
  }

  Future<void> revertPurchaseForExpense(String expenseId) async {
    await ensureLoaded();

    final index = _items.indexWhere((item) => item.expenseId == expenseId);
    if (index < 0) return;

    _items[index] = _items[index].copyWith(clearPurchase: true);
    await _persist();
    notifyListeners();
  }

  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> upserts,
    required List<SyncTombstone> deletes,
  }) async {
    await ensureLoaded();

    final changed = mergeRemoteRecords<ShoppingItem>(
      items: _items,
      upserts: [
        for (final raw in upserts)
          if (ShoppingItem.fromSync(raw) != null) ShoppingItem.fromSync(raw)!,
      ],
      deletes: deletes,
      collection: SyncCollection.shoppingItems,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    if (!changed) return;

    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _persist();
    notifyListeners();
  }

  void resetCache() {
    _items.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(itemsKey) ?? const [];

    _items
      ..clear()
      ..addAll(stored.map(ShoppingItem.decode).whereType<ShoppingItem>())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      itemsKey,
      _items.map((item) => item.encode()).toList(),
    );
    await SyncDirty.mark();
  }

  static int _sequence = 0;

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
}
