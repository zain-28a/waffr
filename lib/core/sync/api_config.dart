// Resolves the FastAPI base URL for sync and auth HTTP calls.

import 'package:waffer/core/prefs/app_prefs.dart';

// Default backend host, overridable via a SharedPreferences key for debug.
class ApiConfig {
  ApiConfig._();

  static const String overrideKey = 'waffer_api_base_url';

  // Dev default; with USB debugging, adb reverse can map this to the PC.
  static const String defaultBaseUrl = 'http://10.194.25.4:8001';

  // Prefer the prefs override when set; strip a trailing slash for path joins.
  static Future<String> baseUrl() async {
    final prefs = await AppPrefs.instance;
    final override = prefs.getString(overrideKey)?.trim() ?? '';
    if (override.isEmpty) return defaultBaseUrl;
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }
}
