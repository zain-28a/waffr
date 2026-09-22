import 'package:shared_preferences/shared_preferences.dart';

/// Base URL for the FastAPI backend.
///
/// Override with the `waffer_api_base_url` preference if needed.
class ApiConfig {
  ApiConfig._();

  static const String overrideKey = 'waffer_api_base_url';

  /// USB debugging: `adb reverse tcp:8000 tcp:8000` then this reaches the PC.
  static const String defaultBaseUrl = 'http://10.164.73.4:8001';

  static Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString(overrideKey)?.trim() ?? '';
    if (override.isEmpty) return defaultBaseUrl;
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }
}
