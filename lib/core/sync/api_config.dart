// Resolves the FastAPI base URL for sync and auth HTTP calls.

import 'package:waffer/core/prefs/app_prefs.dart';

// Default backend host, overridable via a SharedPreferences key for debug.
class ApiConfig {
  ApiConfig._();

  static const String overrideKey = 'waffer_api_base_url';

  // Dev default; with USB debugging, adb reverse can map this to the PC.
  static const String defaultBaseUrl = 'http://192.168.1.109:8001';

  // Free Render instances take about a minute to wake after they sleep.
  static Duration timeoutFor(
    String baseUrl, {
    Duration local = const Duration(seconds: 25),
  }) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host == 'onrender.com' || host.endsWith('.onrender.com')) {
      return const Duration(seconds: 75);
    }
    return local;
  }

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
