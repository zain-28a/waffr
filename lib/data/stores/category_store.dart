// Custom expense categories: local prefs, sync merge, and lookup hook for charts.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/data/models/expense_categories.dart';
import 'package:waffr/core/sync/sync_clock.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_merge.dart';
import 'package:waffr/core/sync/sync_tombstones.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

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
//
// Built-in categories can be removed too. They are only hidden from the
// pickers (the label list travels with settings sync), so old expenses keep
// their label, icon and color. Removed custom categories are kept in a local
// archive for the same reason.
class CategoryStore extends ChangeNotifier {
  CategoryStore._() {
    customCategoryLookup = findCustom;
  }

  static final CategoryStore instance = CategoryStore._();

  static const String itemsKey = 'custom_expense_categories';
  static const String itemsJsonKey = 'custom_expense_categories_v2';
  static const String hiddenBuiltInsKey = 'hidden_builtin_categories';
  static const String archivedKey = 'archived_expense_categories';

  final List<CustomCategoryEntry> _entries = [];
  final Set<String> _hiddenBuiltIns = {};
  final Map<String, CustomCategoryEntry> _archived = {};
  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<ExpenseCategory> get customCategories =>
      [for (final entry in _entries) entry.toCategory()];

  List<CustomCategoryEntry> get entries => List.unmodifiable(_entries);

  /// Built-in labels the user removed, in catalog order (for settings sync).
  List<String> get hiddenBuiltIns => [
        for (final item in expenseCategories)
          if (_hiddenBuiltIns.contains(item.label)) item.label,
      ];

  // Visible built-ins plus customs for pickers; excludes the "custom" tile.
  List<ExpenseCategory> get selectableCategories => [
        for (final item in expenseCategories)
          if (!_hiddenBuiltIns.contains(item.label)) item,
        ...customCategories,
      ];

  /// First category a new expense starts on.
  String get defaultLabel {
    final options = selectableCategories;
    return options.isEmpty ? fallbackCategory.label : options.first.label;
  }

  Future<void> ensureLoaded() => _loader ??= _load();

  // Live custom categories first, then removed ones so history keeps its icon.
  ExpenseCategory? findCustom(String label) {
    for (final entry in _entries) {
      if (entry.label == label) return entry.toCategory();
    }
    return _archived[label]?.toCategory();
  }

  bool isCustom(String label) =>
      _entries.any((entry) => entry.label == label);

  bool isBuiltIn(String label) =>
      expenseCategories.any((item) => item.label == label);

  bool isSelectable(String label) =>
      selectableCategories.any((item) => item.label == label);

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
    // A removed built-in comes back through "add", not through a rename.
    if (ignoring != null && name != ignoring && isBuiltIn(name)) {
      return 'هذا التصنيف موجود مسبقاً';
    }
    return null;
  }

  Future<String?> addCustom(String rawName, {int iconIndex = 0}) async {
    await ensureLoaded();

    if (validateName(rawName) != null) return null;

    final name = rawName.trim();

    // Typing the name of a removed built-in brings that built-in back.
    if (_hiddenBuiltIns.remove(name)) {
      await _persistHidden();
      notifyListeners();
      return name;
    }

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
    _archive(_entries[index]);
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
    _archive(removed!);
    await _persist();
    notifyListeners();
    return true;
  }

  /// Removes a built-in or custom category from the pickers. Expenses that
  /// already use it are not touched.
  Future<bool> removeCategory(String label) async {
    await ensureLoaded();
    if (isCustom(label)) return removeCustom(label);
    if (!isBuiltIn(label) || !_hiddenBuiltIns.add(label)) return false;
    await _persistHidden();
    notifyListeners();
    return true;
  }

  /// Settings sync: the remote list of removed built-ins replaces ours.
  Future<void> applyRemoteHidden(Object? raw) async {
    if (raw is! List) return;
    await ensureLoaded();
    final next = {
      for (final item in raw)
        if (isBuiltIn(item.toString())) item.toString(),
    };
    if (next.length == _hiddenBuiltIns.length &&
        next.containsAll(_hiddenBuiltIns)) {
      return;
    }
    _hiddenBuiltIns
      ..clear()
      ..addAll(next);
    await _persistHidden(markDirty: false);
    notifyListeners();
  }

  void _archive(CustomCategoryEntry entry) {
    _archived[entry.label] = entry;
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
    final previous = List<CustomCategoryEntry>.of(_entries);

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
    for (final entry in previous) {
      final live = _entries.any(
        (item) => item.id == entry.id && item.label == entry.label,
      );
      if (!live) _archive(entry);
    }
    await _persist();
    notifyListeners();
  }

  void resetCache() {
    _entries.clear();
    _hiddenBuiltIns.clear();
    _archived.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    _hiddenBuiltIns
      ..clear()
      ..addAll(prefs.getStringList(hiddenBuiltInsKey) ?? const []);
    _archived.clear();
    for (final entry in _parseJson(prefs.getString(archivedKey) ?? '')) {
      _archived[entry.label] = entry;
    }
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
    await prefs.setString(
      archivedKey,
      jsonEncode([for (final entry in _archived.values) entry.toJson()]),
    );
    await SyncDirty.mark();
  }

  Future<void> _persistHidden({bool markDirty = true}) async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(hiddenBuiltInsKey, hiddenBuiltIns);
    if (markDirty) await SyncDirty.mark(settings: true);
  }
}
