import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/sync/api_config.dart';

/// Device JWT plus a Drive-backupable password so the same email can log in
/// again after reinstall. Ownership always comes from the token, never Flutter.
class AuthSession {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  static const String tokenKey = 'waffer_sync_token';
  static const String passwordKey = 'waffer_sync_password';
  static const String lastSyncKey = 'waffer_last_sync_at';

  static const Duration _timeout = Duration(seconds: 15);

  Future<String?> email() async {
    final prefs = await SharedPreferences.getInstance();
    final google = prefs.getString(BackupService.linkedEmailKey)?.trim() ?? '';
    if (google.contains('@')) return google.toLowerCase();
    final local = prefs.getString('user_email')?.trim() ?? '';
    if (local.contains('@')) return local.toLowerCase();
    return null;
  }

  Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(tokenKey)?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(lastSyncKey) ?? '')?.toUtc();
  }

  Future<void> saveLastSyncAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastSyncKey, value.toUtc().toIso8601String());
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(lastSyncKey);
  }

  /// Returns a JWT or `null` when the user has no email / is offline.
  Future<String?> ensureToken() async {
    final address = await email();
    if (address == null) return null;

    final existing = await token();
    if (existing != null) {
      if (await _tokenWorks(existing)) return existing;
      await clearToken();
    }

    return _loginOrRegister(address);
  }

  Future<String?> _loginOrRegister(String address) async {
    final prefs = await SharedPreferences.getInstance();
    var password = prefs.getString(passwordKey)?.trim() ?? '';
    if (password.isEmpty) {
      password = _generatePassword();
      await prefs.setString(passwordKey, password);
    }

    final name = prefs.getString('user_name')?.trim();
    final base = await ApiConfig.baseUrl();

    var token = await _postAuth(
      Uri.parse('$base/auth/login'),
      {'email': address, 'password': password},
    );
    if (token != null) {
      await _storeToken(token);
      return token;
    }

    token = await _postAuth(
      Uri.parse('$base/auth/register'),
      {
        'email': address,
        'password': password,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    if (token != null) {
      await _storeToken(token);
      return token;
    }

    token = await _postAuth(
      Uri.parse('$base/auth/login'),
      {'email': address, 'password': password},
    );
    if (token != null) {
      await _storeToken(token);
    }
    return token;
  }

  Future<void> _storeToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, value);
  }

  Future<bool> _tokenWorks(String value) async {
    try {
      final base = await ApiConfig.baseUrl();
      final response = await http
          .get(
            Uri.parse('$base/auth/me'),
            headers: {'Authorization': 'Bearer $value'},
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _postAuth(Uri uri, Map<String, String> body) async {
    try {
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final token = decoded['access_token']?.toString();
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  static String _generatePassword() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
