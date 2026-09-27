// Custom expense categories: local prefs, sync merge, and lookup hook for charts.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_merge.dart';
import 'package:waffer/core/sync/sync_tombstones.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

// One user-defined category with a chosen icon index.
class CustomCategoryEntry {
  final String id;
  final String label;
  final int iconIndex;
  final int? colorIndex;
  final DateTime? updatedAt;

  const CustomCategoryEntry({
    required this.id,
    required this.label,
    required this.iconIndex,
    this.colorIndex,
    this.updatedAt,
  });

  DateTime get syncUpdatedAt => (updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc();

  ExpenseCategory toCategory() => customCategoryNamed(
        label,
        iconIndex: iconIndex,
        colorIndex: colorIndex,
      );

  CustomCategoryEntry copyWith({
    String? label,
    int? iconIndex,
    int? colorIndex,
    DateTime? updatedAt,
  }) {
    return CustomCategoryEntry(
      id: id,
      label: label ?? this.label,
      iconIndex: iconIndex ?? this.iconIndex,
      colorIndex: colorIndex ?? this.colorIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': iconIndex,
        if (colorIndex != null) 'color': colorIndex,
        'updatedAt': toSyncIso(syncUpdatedAt),
      };

  Map<String, dynamic> toSyncJson() => {
        'client_id': id,
        'label': label,
        'icon_index': iconIndex,
        'updated_at': toSyncIso(syncUpdatedAt),
      };

  factory CustomCategoryEntry.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] as String? ?? '').trim();
    final icon = json['icon'] ?? json['icon_index'] ?? json['iconIndex'];
    final iconIndex = icon is int
        ? icon
        : int.tryParse(icon?.toString() ?? '') ?? 0;
    final rawId = (json['id'] ?? json['client_id'])?.toString().trim() ?? '';
    return CustomCategoryEntry(
      id: rawId.isEmpty ? _legacyCategoryId(label) : rawId,
      label: label,
      iconIndex: clampCustomIconIndex(iconIndex),
      colorIndex: _readColorIndex(json['color'] ?? json['color_index']),
      updatedAt: parseSyncDate(json['updatedAt'] ?? json['updated_at']) ??
          syncNow(),
    );
  }

  // Server payload → entry; null when label or client id is missing.
  static CustomCategoryEntry? fromSync(Map<String, dynamic> raw) {
    final label = raw['label']?.toString().trim() ?? '';
    final id = (raw['client_id'] ?? raw['id'])?.toString().trim() ?? '';
    if (label.isEmpty || id.isEmpty) return null;
    final icon = raw['icon_index'] ?? raw['iconIndex'] ?? raw['icon'];
    final iconIndex = icon is int
        ? icon
        : int.tryParse(icon?.toString() ?? '') ?? 0;
    return CustomCategoryEntry(
      id: id,
      label: label,
      iconIndex: clampCustomIconIndex(iconIndex),
      colorIndex: _readColorIndex(raw['color'] ?? raw['color_index']),
      updatedAt: parseSyncDate(raw['updated_at'] ?? raw['updatedAt']),
    );
  }
}

int? _readColorIndex(Object? raw) {
  if (raw == null) return null;
  final index = raw is int ? raw : int.tryParse(raw.toString());
  if (index == null || customCategoryColors.isEmpty) return null;
  return clampCustomColorIndex(index);
}

// Stable id for pre-v2 categories that only stored a label string.
String _legacyCategoryId(String label) {
  var hash = 0;
  for (final unit in label.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return 'cat_$hash';
}

int _categorySeq = 0;

String _newCategoryId() =>
    'cat_${DateTime.now().microsecondsSinceEpoch}_${_categorySeq++}';

// Owns custom categories in prefs and registers them with customCategoryLookup.
class CategoryStore extends ChangeNotifier {
  CategoryStore._() {
    customCategoryLookup = findCustom;
  }

  static final CategoryStore instance = CategoryStore._();

  static const String itemsKey = 'custom_expense_categories';
  static const String itemsJsonKey = 'custom_expense_categories_v2';

  final List<CustomCategoryEntry> _entries = [];
  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<ExpenseCategory> get customCategories =>
      [for (final entry in _entries) entry.toCategory()];

  List<CustomCategoryEntry> get entries => List.unmodifiable(_entries);

  // Built-ins plus customs for pickers; excludes the "custom" action tile.
  List<ExpenseCategory> get selectableCategories => [
        ...expenseCategories,
        ...customCategories,
      ];

  Future<void> ensureLoaded() => _loader ??= _load();

  ExpenseCategory? findCustom(String label) {
    for (final entry in _entries) {
      if (entry.label == label) return entry.toCategory();
    }
    return null;
  }

  bool isCustom(String label) =>
      _entries.any((entry) => entry.label == label);

  int iconIndexOf(String label) {
    for (final entry in _entries) {
      if (entry.label == label) return entry.iconIndex;
    }
    return 0;
  }

  // Arabic validation error, or null if the name can be used.
  String? validateName(String rawName, {String? ignoring}) {
    final name = rawName.trim();
    if (name.isEmpty) return 'أدخل اسماً للتصنيف';
    if (name == customCategoryActionLabel ||
        name == fallbackCategory.label) {
      return 'هذا الاسم محجوز';
    }
    if (selectableCategories.any(
      (item) => item.label == name && item.label != ignoring,
    )) {
      return 'هذا التصنيف موجود مسبقاً';
    }
    return null;
  }

  Future<String?> addCustom(String rawName, {int iconIndex = 0}) async {
    await ensureLoaded();

    if (validateName(rawName) != null) return null;

    final name = rawName.trim();
    _entries.add(
      CustomCategoryEntry(
        id: _newCategoryId(),
        label: name,
        iconIndex: clampCustomIconIndex(iconIndex),
        colorIndex: nextCustomColorIndex(
          _entries.map((entry) => entry.colorIndex).whereType<int>(),
        ),
        updatedAt: syncNow(),
      ),
    );
    await _persist();
    notifyListeners();
    return name;
  }

  Future<String?> renameCustom(
    String oldLabel,
    String rawName, {
    int? iconIndex,
  }) async {
    await ensureLoaded();

    final index = _entries.indexWhere((entry) => entry.label == oldLabel);
    if (index < 0) return null;

    final error = validateName(rawName, ignoring: oldLabel);
    if (error != null) return null;

    final name = rawName.trim();
    _entries[index] = _entries[index].copyWith(
      label: name,
      iconIndex: clampCustomIconIndex(iconIndex ?? _entries[index].iconIndex),
      updatedAt: syncNow(),
    );
    await _persist();
    notifyListeners();
    return name;
  }

  // Removes the category and records a sync tombstone.
  Future<bool> removeCustom(String label) async {
    await ensureLoaded();

    final before = _entries.length;
    CustomCategoryEntry? removed;
    _entries.removeWhere((entry) {
      if (entry.label != label) return false;
      removed = entry;
      return true;
    });
    if (_entries.length == before || removed == null) return false;

    await SyncTombstones.instance.add(
      SyncCollection.expenseCategories,
      removed!.id,
    );
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> applyRemoteSync({
    required List<Map<String, dynamic>> upserts,
    required List<SyncTombstone> deletes,
  }) async {
    await ensureLoaded();

    final previousColors = {
      for (final entry in _entries)
        if (entry.colorIndex != null) entry.id: entry.colorIndex!,
    };

    final changed = mergeRemoteRecords<CustomCategoryEntry>(
      items: _entries,
      upserts: [
        for (final raw in upserts)
          if (CustomCategoryEntry.fromSync(raw) != null)
            CustomCategoryEntry.fromSync(raw)!,
      ],
      deletes: deletes,
      collection: SyncCollection.expenseCategories,
      idOf: (item) => item.id,
      updatedOf: (item) => item.syncUpdatedAt,
    );

    for (var i = 0; i < _entries.length; i++) {
      final kept = previousColors[_entries[i].id];
      if (_entries[i].colorIndex == null && kept != null) {
        _entries[i] = _entries[i].copyWith(colorIndex: kept);
      }
    }
    final filled = _assignMissingColors();

    if (!changed && !filled) return;
    await _persist();
    notifyListeners();
  }

  void resetCache() {
    _entries.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    _entries
      ..clear()
      ..addAll(await _readEntries(prefs));
    if (_assignMissingColors()) {
      await _persist();
    }
    _loaded = true;
    notifyListeners();
  }

  // Gives each saved category its own palette slot when none was stored.
  bool _assignMissingColors() {
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].colorIndex != null) continue;
      final used = _entries.map((entry) => entry.colorIndex).whereType<int>();
      _entries[i] = _entries[i].copyWith(colorIndex: nextCustomColorIndex(used));
      changed = true;
    }
    return changed;
  }

  // Prefers v2 JSON; migrates the old string-list format when needed.
  Future<List<CustomCategoryEntry>> _readEntries(SharedPreferences prefs) async {
    final json = prefs.getString(itemsJsonKey);
    if (json != null && json.trim().isNotEmpty) {
      final parsed = _parseJson(json);
      if (parsed.isNotEmpty && !json.contains('"id"')) {
        _entries
          ..clear()
          ..addAll(parsed);
        await _persist();
      }
      return parsed;
    }

    final legacy = prefs.getStringList(itemsKey) ?? const [];
    final migrated = [
      for (final raw in legacy)
        if (raw.trim().isNotEmpty)
          CustomCategoryEntry(
            id: _legacyCategoryId(raw.trim()),
            label: raw.trim(),
            iconIndex: raw.hashCode.abs() % customCategoryIconChoices.length,
            updatedAt: syncNow(),
          ),
    ];
    if (migrated.isNotEmpty) {
      _entries
        ..clear()
        ..addAll(migrated);
      await _persist();
    }
    return migrated;
  }

  List<CustomCategoryEntry> _parseJson(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            CustomCategoryEntry.fromJson(item)
          else if (item is Map)
            CustomCategoryEntry.fromJson(Map<String, dynamic>.from(item)),
      ].where((entry) => entry.label.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    final prefs = await AppPrefs.instance;
    await prefs.setString(
      itemsJsonKey,
      jsonEncode([for (final entry in _entries) entry.toJson()]),
    );
    await SyncDirty.mark();
  }
}
