// Auth session: JWT login/register against FastAPI /auth, plus last-sync stamp.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:waffer/data/services/backup_service.dart';
import 'package:waffer/data/models/registration_profile.dart';
import 'package:waffer/core/sync/api_config.dart';
import 'package:waffer/core/sync/auth_errors.dart';
import 'package:waffer/core/sync/profile_sync.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

export 'package:waffer/core/sync/auth_errors.dart';

// Simple success/failure wrapper for login and register UI.
class AuthResult {
  final bool ok;
  final String message;

  const AuthResult.success()
      : ok = true,
        message = '';

  const AuthResult.failure(this.message) : ok = false;
}

// Holds the Bearer token and account email. Server ownership always comes from
// the token; guest mode has no token and never syncs. Switching accounts can
// replace local data so one user's records do not bleed into another's.
class AuthSession {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  static const String tokenKey = 'waffer_sync_token';
  static const String lastSyncKey = 'waffer_last_sync_at';
  static const String accountEmailKey = 'waffer_account_email';
  static const String dataOwnerKey = 'waffer_data_owner_email';
  static const String legacyPasswordKey = 'waffer_sync_password';

  static const Duration _timeout = Duration(seconds: 15);

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> isLoggedIn() async {
    final value = await token();
    return value != null && value.isNotEmpty;
  }

  // Signed-in API email, or null in guest mode.
  Future<String?> email() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getString(accountEmailKey)?.trim() ?? '';
    if (stored.contains('@')) return stored.toLowerCase();
    return null;
  }

  // Email whose local financial data currently lives on this device.
  Future<String?> dataOwnerEmail() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getString(dataOwnerKey)?.trim() ?? '';
    if (stored.contains('@')) return stored.toLowerCase();
    return null;
  }

  Future<String?> token() async {
    await _migrateLegacyToken();
    final value = (await _secure.read(key: tokenKey))?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await AppPrefs.instance;
    return DateTime.tryParse(prefs.getString(lastSyncKey) ?? '')?.toUtc();
  }

  Future<void> saveLastSyncAt(DateTime value) async {
    final prefs = await AppPrefs.instance;
    await prefs.setString(lastSyncKey, value.toUtc().toIso8601String());
  }

  Future<void> clearToken() async {
    await _secure.delete(key: tokenKey);
    final prefs = await AppPrefs.instance;
    await prefs.remove(tokenKey);
  }

  // Drop the API session; local financial data and data-owner stamp stay.
  Future<void> clearSession() async {
    await clearToken();
    final prefs = await AppPrefs.instance;
    await prefs.remove(lastSyncKey);
    await prefs.remove(accountEmailKey);
    await prefs.remove(legacyPasswordKey);
  }

  Future<void> clearDataOwner() async {
    final prefs = await AppPrefs.instance;
    await prefs.remove(dataOwnerKey);
  }

  // Return a live JWT, or null for guests / dead tokens. Never auto-registers.
  Future<String?> ensureToken() async {
    final existing = await token();
    if (existing == null) return null;
    final me = await _fetchMe(existing);
    if (me == null) {
      await clearToken();
      return null;
    }
    final address = me['email']?.toString().trim() ?? '';
    if (address.contains('@')) {
      final prefs = await AppPrefs.instance;
      await prefs.setString(accountEmailKey, address.toLowerCase());
    }
    return existing;
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) {
    return _authenticate(
      path: '/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required RegistrationProfile profile,
  }) {
    return _authenticate(
      path: '/auth/register',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        ...profile.toAuthBody(),
      },
    );
  }

  // POST login or register, store the token, and bind the account locally.
  Future<AuthResult> _authenticate({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final address = body['email']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';
    if (!_looksLikeEmail(address) || password.isEmpty) {
      return const AuthResult.failure('أدخل البريد وكلمة المرور');
    }

    try {
      final base = await ApiConfig.baseUrl();
      final response = await http
          .post(
            Uri.parse('$base$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }

      if (response.statusCode != 200) {
        return AuthResult.failure(describeAuthError(response.statusCode, decoded));
      }

      if (decoded is! Map) {
        return const AuthResult.failure('تعذر قراءة رد الخادم');
      }
      final access = decoded['access_token']?.toString() ?? '';
      if (access.isEmpty) {
        return const AuthResult.failure('تعذر قراءة رد الخادم');
      }

      final me = await _fetchMe(access);
      final resolvedEmail = (me?['email']?.toString() ?? address).toLowerCase();

      await _bindAccount(
        email: resolvedEmail,
        token: access,
        profile: _mergedProfile(me, body),
      );
      return const AuthResult.success();
    } catch (_) {
      return const AuthResult.failure(
        'لا يوجد اتصال. تحقق من الشبكة وحاول مرة أخرى',
      );
    }
  }

  // Attach token + email; wipe local data when adopting a different owner.
  Future<void> _bindAccount({
    required String email,
    required String token,
    required Map<String, dynamic> profile,
  }) async {
    final owner = await dataOwnerEmail();
    final adopting = owner != email;
    if (owner != null && adopting) {
      await BackupService.instance.replaceLocalDataForAccountSwitch();
      final prefs = await AppPrefs.instance;
      await prefs.remove(lastSyncKey);
    }

    await _storeToken(token);

    final prefs = await AppPrefs.instance;
    await prefs.setString(accountEmailKey, email);
    await prefs.setString(dataOwnerKey, email);
    await prefs.setBool(BackupService.authChoiceKey, true);
    await prefs.setString('user_email', email);
    await prefs.remove(legacyPasswordKey);
    await prefs.remove(tokenKey);

    if (adopting) {
      await ProfileSync.adoptAccount(profile);
    } else {
      await ProfileSync.fillMissing(profile);
    }
  }

  Map<String, dynamic> _mergedProfile(
    Map<String, dynamic>? me,
    Map<String, dynamic> body,
  ) {
    const fields = [
      'name',
      'gender',
      'birthdate',
      'country',
      'city',
      'street',
    ];
    final profile = <String, dynamic>{};
    for (final field in fields) {
      if (me != null && me.containsKey(field)) {
        profile[field] = me[field];
      } else if (body.containsKey(field)) {
        profile[field] = body[field];
      }
    }
    return profile;
  }

  Future<void> _storeToken(String value) async {
    await _secure.write(key: tokenKey, value: value);
  }

  // Move an old prefs-stored JWT into secure storage once.
  Future<void> _migrateLegacyToken() async {
    final prefs = await AppPrefs.instance;
    final legacy = prefs.getString(tokenKey)?.trim() ?? '';
    if (legacy.isEmpty) return;
    final current = (await _secure.read(key: tokenKey))?.trim() ?? '';
    if (current.isEmpty) {
      await _secure.write(key: tokenKey, value: legacy);
    }
    await prefs.remove(tokenKey);
    await prefs.remove(legacyPasswordKey);
  }

  // Validate the token with GET /auth/me and return the profile payload.
  Future<Map<String, dynamic>?> _fetchMe(String token) async {
    try {
      final base = await ApiConfig.baseUrl();
      final response = await http
          .get(
            Uri.parse('$base/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeEmail(String value) {
    final trimmed = value.trim();
    return trimmed.contains('@') && trimmed.contains('.');
  }
}
