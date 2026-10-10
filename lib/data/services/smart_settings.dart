// On/off switches for the smart features. Both run on the device and
// start on; the AI settings screen turns them off.

import 'package:flutter/foundation.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

class SmartSettings extends ChangeNotifier {
  SmartSettings._();

  static final SmartSettings instance = SmartSettings._();

  static const String alertsKey = 'smart_alerts_enabled';
  static const String categorizeKey = 'smart_categorize_enabled';

  bool _alerts = true;
  bool _categorize = true;
  Future<void>? _loader;

  // Balance forecast and other smart notifications.
  bool get alerts => _alerts;

  // Picking the category from the note while adding an expense.
  bool get categorize => _categorize;

  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    _alerts = prefs.getBool(alertsKey) ?? true;
    _categorize = prefs.getBool(categorizeKey) ?? true;
    notifyListeners();
  }

  Future<void> setAlerts(bool value) async {
    _alerts = value;
    notifyListeners();
    final prefs = await AppPrefs.instance;
    await prefs.setBool(alertsKey, value);
  }

  Future<void> setCategorize(bool value) async {
    _categorize = value;
    notifyListeners();
    final prefs = await AppPrefs.instance;
    await prefs.setBool(categorizeKey, value);
  }

  // After a local data wipe the defaults come back.
  void resetCache() {
    _alerts = true;
    _categorize = true;
    _loader = null;
    notifyListeners();
  }
}
