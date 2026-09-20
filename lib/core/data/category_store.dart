import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/expense_categories.dart';

class CustomCategoryEntry {
  final String label;
  final int iconIndex;

  const CustomCategoryEntry({
    required this.label,
    required this.iconIndex,
  });

  ExpenseCategory toCategory() =>
      customCategoryNamed(label, iconIndex: iconIndex);

  Map<String, dynamic> toJson() => {
        'label': label,
        'icon': iconIndex,
      };

  factory CustomCategoryEntry.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] as String? ?? '').trim();
    final icon = json['icon'];
    final iconIndex = icon is int
        ? icon
        : int.tryParse(icon?.toString() ?? '') ?? 0;
    return CustomCategoryEntry(
      label: label,
      iconIndex: clampCustomIconIndex(iconIndex),
    );
  }
}

/// تصنيفات المصروف المخصصة، تُحفظ محلياً وتظهر في شبكة التصنيف.
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

  /// التصنيفات القابلة للاختيار: المدمجة ثم المخصصة. «مخصص» ليس منها.
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
        label: name,
        iconIndex: clampCustomIconIndex(iconIndex),
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
    _entries[index] = CustomCategoryEntry(
      label: name,
      iconIndex: clampCustomIconIndex(iconIndex ?? _entries[index].iconIndex),
    );
    await _persist();
    notifyListeners();
    return name;
  }

  Future<bool> removeCustom(String label) async {
    await ensureLoaded();

    final before = _entries.length;
    _entries.removeWhere((entry) => entry.label == label);
    if (_entries.length == before) return false;

    await _persist();
    notifyListeners();
    return true;
  }

  void resetCache() {
    _entries.clear();
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _entries
      ..clear()
      ..addAll(await _readEntries(prefs));
    _loaded = true;
    notifyListeners();
  }

  Future<List<CustomCategoryEntry>> _readEntries(SharedPreferences prefs) async {
    final json = prefs.getString(itemsJsonKey);
    if (json != null && json.trim().isNotEmpty) {
      return _parseJson(json);
    }

    final legacy = prefs.getStringList(itemsKey) ?? const [];
    final migrated = [
      for (final raw in legacy)
        if (raw.trim().isNotEmpty)
          CustomCategoryEntry(
            label: raw.trim(),
            iconIndex: raw.hashCode.abs() % customCategoryIconChoices.length,
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      itemsJsonKey,
      jsonEncode([for (final entry in _entries) entry.toJson()]),
    );
  }
}
