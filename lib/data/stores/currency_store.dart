// Persists which currencies are enabled and which one is active in the UI.

import 'package:flutter/foundation.dart';
import 'package:waffr/data/models/currency.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/sync/sync_dirty.dart';

export 'package:waffr/data/models/currency.dart';

// Enabled list + active code. Removing a currency never deletes its ledger rows.
class CurrencyStore extends ChangeNotifier {
  CurrencyStore._();

  static final CurrencyStore instance = CurrencyStore._();

  static const String enabledKey = 'enabled_currencies';
  static const String activeKey = 'active_currency';

  final List<String> _enabled = [defaultCurrencyCode];
  String _activeCode = defaultCurrencyCode;

  Future<void>? _loader;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  String get activeCode => _activeCode;

  CurrencyInfo get active => Currencies.of(_activeCode);

  String get activeSymbol => active.symbol;

  // Currencies shown in the balance carousel and amount pickers.
  List<CurrencyInfo> get enabledCurrencies {
    return [
      for (final code in _enabled) Currencies.of(code),
    ];
  }

  List<String> get enabledCodes => List.unmodifiable(_enabled);

  // Catalog entries not yet on the enabled list.
  List<CurrencyInfo> get availableToAdd {
    return [
      for (final item in Currencies.catalog)
        if (!_enabled.contains(item.code)) item,
    ];
  }

  bool isEnabled(String code) => _enabled.contains(Currencies.normalize(code));

  Future<void> ensureLoaded() => _loader ??= _load();

  // Switches the active currency if it is already enabled.
  Future<void> setActive(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (!_enabled.contains(normalized)) {
      return;
    }
    if (_activeCode == normalized) {
      return;
    }

    _activeCode = normalized;
    await _persistActive();
    await SyncDirty.mark(settings: true);
    notifyListeners();
  }

  // Replaces the enabled list and active code from a newer account sync.
  Future<void> applyRemote({
    List<dynamic>? enabled,
    String? active,
  }) async {
    await ensureLoaded();
    if (enabled == null && (active == null || active.trim().isEmpty)) return;

    if (enabled != null) {
      _enabled
        ..clear()
        ..add(defaultCurrencyCode);
      for (final raw in enabled) {
        final code = Currencies.normalize(raw?.toString());
        if (code == defaultCurrencyCode) continue;
        if (!Currencies.isKnown(code)) continue;
        if (_enabled.contains(code)) continue;
        _enabled.add(code);
      }
    }

    final nextActive = Currencies.normalize(active ?? _activeCode);
    _activeCode = _enabled.contains(nextActive) ? nextActive : defaultCurrencyCode;
    await _persistEnabled();
    await _persistActive();
    notifyListeners();
  }

  Future<void> selectNext() async {
    await ensureLoaded();
    if (_enabled.length < 2) return;

    final index = _enabled.indexOf(_activeCode);
    final next = (index < 0 ? 0 : index + 1) % _enabled.length;
    await setActive(_enabled[next]);
  }

  Future<void> selectPrevious() async {
    await ensureLoaded();
    if (_enabled.length < 2) return;

    final index = _enabled.indexOf(_activeCode);
    final previous = (index < 0 ? 0 : index - 1 + _enabled.length) %
        _enabled.length;
    await setActive(_enabled[previous]);
  }

  // Adds a known non-SYP currency to the enabled list.
  Future<bool> addCurrency(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (normalized == defaultCurrencyCode) {
      return false;
    }
    if (!Currencies.isKnown(normalized) || _enabled.contains(normalized)) {
      return false;
    }

    _enabled.add(normalized);
    await _persistEnabled();
    await SyncDirty.mark(settings: true);
    notifyListeners();
    return true;
  }

  // Drops a currency from the carousel without wiping its transactions.
  Future<bool> removeCurrency(String code) async {
    await ensureLoaded();

    final normalized = Currencies.normalize(code);
    if (normalized == defaultCurrencyCode) {
      return false;
    }
    if (!_enabled.contains(normalized)) {
      return false;
    }

    _enabled.remove(normalized);
    if (_activeCode == normalized) {
      _activeCode = defaultCurrencyCode;
      await _persistActive();
    }
    await _persistEnabled();
    await SyncDirty.mark(settings: true);
    notifyListeners();
    return true;
  }

  void resetCache() {
    _enabled
      ..clear()
      ..add(defaultCurrencyCode);
    _activeCode = defaultCurrencyCode;
    _loaded = false;
    _loader = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getStringList(enabledKey) ?? const [];

    _enabled
      ..clear()
      ..add(defaultCurrencyCode);

    for (final raw in stored) {
      final code = Currencies.normalize(raw);
      if (code == defaultCurrencyCode) continue;
      if (!Currencies.isKnown(code)) continue;
      if (_enabled.contains(code)) continue;
      _enabled.add(code);
    }

    final active = Currencies.normalize(prefs.getString(activeKey));
    _activeCode = _enabled.contains(active) ? active : defaultCurrencyCode;

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persistEnabled() async {
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(enabledKey, _enabled);
  }

  Future<void> _persistActive() async {
    final prefs = await AppPrefs.instance;
    await prefs.setString(activeKey, _activeCode);
  }
}
