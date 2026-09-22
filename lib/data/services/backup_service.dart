import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/services/drive_backup_client.dart';
import 'package:waffer/data/services/google_auth_service.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/data/services/profile_photo.dart';
import 'package:waffer/data/stores/recurring_expense_store.dart';
import 'package:waffer/data/stores/shopping_list_store.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/sync/api_config.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

/// نتيجة محاولة ربط Google Drive للنسخة الاحتياطية فقط.
enum GoogleLinkResult {
  /// وُجدت نسخة احتياطية وتمت استعادتها.
  restored,

  /// تم الربط بنجاح لكن لا توجد نسخة سابقة.
  noBackup,

  /// ألغى المستخدم العملية أو فشل تسجيل الدخول.
  failed,
}

/// حساب Google مرتبط يُعرض في مبدّل الحسابات.
class LinkedGoogleAccount {
  final String email;
  final String googleName;
  final String? photoUrl;
  final String? localName;

  const LinkedGoogleAccount({
    required this.email,
    this.googleName = '',
    this.photoUrl,
    this.localName,
  });

  String get displayName {
    final edited = localName?.trim() ?? '';
    if (edited.isNotEmpty) return edited;

    final google = googleName.trim();
    if (google.isNotEmpty) return google;

    return email;
  }

  LinkedGoogleAccount copyWith({
    String? googleName,
    String? photoUrl,
    String? localName,
  }) {
    return LinkedGoogleAccount(
      email: email,
      googleName: googleName ?? this.googleName,
      photoUrl: photoUrl ?? this.photoUrl,
      localName: localName ?? this.localName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'email': email,
    'googleName': googleName,
    'photoUrl': photoUrl,
    'localName': localName,
  };

  static LinkedGoogleAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final email = raw['email']?.toString().trim() ?? '';
    if (email.isEmpty) return null;

    return LinkedGoogleAccount(
      email: email,
      googleName: raw['googleName']?.toString() ?? '',
      photoUrl: _text(raw['photoUrl']),
      localName: _text(raw['localName']),
    );
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// نسخ بيانات `SharedPreferences` احتياطياً إلى مجلد بيانات
/// التطبيق في Google Drive، واستعادتها عند إعادة التثبيت.
///
/// المزامنة انتهازية بالكامل: تحدث فقط عند توفر الإنترنت
/// وحساب مرتبط، وأي فشل يُتجاهل بصمت.
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  /// Off while FastAPI sync is the cloud path. Flip to re-enable Drive.
  static const bool driveBackupEnabled = false;

  /// مفتاح يدل على أن المستخدم تجاوز شاشة الدخول
  /// (سواء بحساب أو كضيف).
  static const String authChoiceKey = 'auth_choice_made';

  /// هل الحساب مرتبط بـ Google.
  static const String linkedKey = 'google_linked';

  /// بريد الحساب المرتبط، لعرضه في الإعدادات.
  static const String linkedEmailKey = 'google_email';

  /// صورة الحساب الحالي من Google، للعرض دون شبكة إن أمكن.
  static const String linkedPhotoKey = 'google_photo_url';

  /// قائمة الحسابات المرتبطة على هذا الجهاز.
  static const String accountsKey = 'google_accounts';

  /// لم يُحسم بعد إن كانت هناك نسخة على Drive
  /// (فشل الاتصال عند تسجيل الدخول). لا يُرفع شيء حتى يُحسم الأمر.
  static const String restorePendingKey = 'google_restore_pending';

  /// مفاتيح محلية بحتة لا تُرفع ولا تُستعاد،
  /// لأنها تصف حالة الجهاز الحالي لا بيانات المستخدم.
  static const Set<String> _localOnlyKeys = <String>{
    authChoiceKey,
    linkedKey,
    linkedEmailKey,
    linkedPhotoKey,
    accountsKey,
    restorePendingKey,
    AuthSession.tokenKey,
    AuthSession.lastSyncKey,
    AuthSession.accountEmailKey,
    AuthSession.dataOwnerKey,
    AuthSession.legacyPasswordKey,
    ApiConfig.overrideKey,
    ProfilePhoto.prefsKey,
    ProfilePhoto.updatedAtKey,
    ProfilePhoto.pendingKey,
  };

  static const int _schemaVersion = 1;

  static const Duration _debounce = Duration(seconds: 2);

  Timer? _debounceTimer;
  bool _uploading = false;
  bool _pending = false;
  bool _restoring = false;
  bool _listenersAttached = false;
  String? _cachedFileId;

  final List<VoidCallback> _restoreListeners = <VoidCallback>[];

  /// يُستدعى بعد استعادة نسخة من Drive بينما التطبيق يعمل،
  /// حتى يعيد مسار الإقلاع قراءة الحالة (تجاوز شاشة المعلومات مثلاً).
  void addRestoreListener(VoidCallback listener) {
    _restoreListeners.add(listener);
  }

  void removeRestoreListener(VoidCallback listener) {
    _restoreListeners.remove(listener);
  }

  /// يُستدعى مرة واحدة عند إقلاع التطبيق.
  ///
  /// يستعيد جلسة Google السابقة إن وُجدت، ثم يرفع أي تغييرات
  /// حدثت أثناء عدم توفر الإنترنت.
  Future<void> initialize() async {
    if (!driveBackupEnabled) return;

    _attachListeners();

    final prefs = await AppPrefs.instance;

    if (!(prefs.getBool(linkedKey) ?? false)) {
      return;
    }

    final account = await GoogleAuthService.instance.restoreSession();

    if (account == null) {
      return;
    }

    if (prefs.getBool(restorePendingKey) ?? false) {
      if (!await _completePendingRestore()) {
        return;
      }
    }

    scheduleBackup();
  }

  /// يطلب رفع نسخة محدّثة. الاستدعاء رخيص وغير حاجب،
  /// ويُجمَّع عدة مرات متتالية في رفعة واحدة.
  void scheduleBackup() {
    if (!driveBackupEnabled || _restoring) {
      return;
    }

    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounce, () {
      unawaited(_uploadNow());
    });
  }

  /// يرفع النسخة الحالية فوراً. يرجع `true` عند نجاح الرفع.
  Future<bool> flushBackup() async {
    if (!driveBackupEnabled) return false;

    _debounceTimer?.cancel();

    for (var i = 0; i < 25 && _uploading; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return _uploadNow();
  }

  // ==========================================
  // تسجيل الدخول والخروج
  // ==========================================

  /// يربط Google Drive ويستعيد النسخة الاحتياطية إن وُجدت.
  ///
  /// هذا ليس تسجيل دخول إلى حساب وفّر.
  Future<GoogleLinkResult> signInAndRestore() async {
    if (!driveBackupEnabled) return GoogleLinkResult.failed;

    final auth = GoogleAuthService.instance;

    final account = await auth.signIn();

    if (account == null) {
      return GoogleLinkResult.failed;
    }

    final headers = await auth.authHeaders(promptIfNecessary: true);

    if (headers == null) {
      await _markLinked(account.email, restorePending: true);
      return GoogleLinkResult.noBackup;
    }

    final lookup = await DriveBackupClient.lookupBackup(headers);

    if (lookup.failed) {
      await _markLinked(account.email, restorePending: true);
      return GoogleLinkResult.noBackup;
    }

    var restored = false;

    if (lookup.exists) {
      _cachedFileId = lookup.fileId;

      final content = await DriveBackupClient.downloadBackup(
        headers,
        lookup.fileId!,
      );

      if (content != null) {
        restored = await _restoreFromJson(content, replaceExisting: true);
      }
    }

    await _markLinked(account.email, restorePending: false);

    scheduleBackup();

    return restored ? GoogleLinkResult.restored : GoogleLinkResult.noBackup;
  }

  /// ربط حساب من داخل الإعدادات.
  ///
  /// لا يستعيد أي نسخة سابقة لأن الجهاز يحتوي بيانات عاملة،
  /// بل يرفع الحالة الحالية لتصبح هي النسخة المعتمدة.
  Future<bool> linkAccount() async {
    if (!driveBackupEnabled) return false;

    final account = await GoogleAuthService.instance.signIn();

    if (account == null) {
      return false;
    }

    // طلب إذن Drive الآن بينما التفاعل قائم.
    await GoogleAuthService.instance.authHeaders(promptIfNecessary: true);

    _cachedFileId = null;

    await _markLinked(account.email, restorePending: false);

    scheduleBackup();

    return true;
  }

  /// إضافة حساب Google آخر ثم استعادة بياناته من Drive.
  Future<GoogleLinkResult> addOrSwitchAccount() async {
    if (!driveBackupEnabled) return GoogleLinkResult.failed;

    final linked = await isLinked();

    if (linked) {
      final uploaded = await flushBackup();
      if (!uploaded) {
        return GoogleLinkResult.failed;
      }
    }

    await GoogleAuthService.instance.signOut();
    _cachedFileId = null;

    final account = await GoogleAuthService.instance.signIn();

    if (account == null) {
      await GoogleAuthService.instance.restoreSession();
      return GoogleLinkResult.failed;
    }

    final headers = await GoogleAuthService.instance.authHeaders(
      promptIfNecessary: true,
    );

    if (headers == null) {
      await _markLinked(account.email, restorePending: true);
      await _clearRestorableData();
      _notifyRestored();
      return GoogleLinkResult.noBackup;
    }

    final lookup = await DriveBackupClient.lookupBackup(headers);

    if (lookup.failed) {
      await _markLinked(account.email, restorePending: true);
      await _clearRestorableData();
      _notifyRestored();
      return GoogleLinkResult.noBackup;
    }

    var restored = false;

    if (lookup.exists) {
      _cachedFileId = lookup.fileId;

      final content = await DriveBackupClient.downloadBackup(
        headers,
        lookup.fileId!,
      );

      if (content != null) {
        restored = await _restoreFromJson(content, replaceExisting: true);
      }
    } else {
      await _clearRestorableData();
    }

    await _markLinked(account.email, restorePending: false);

    if (!lookup.exists) {
      scheduleBackup();
    }

    _notifyRestored();

    return restored ? GoogleLinkResult.restored : GoogleLinkResult.noBackup;
  }

  /// يمسح البيانات المحلية القابلة للمزامنة قبل حساب آخر، دون المساس بجلسة Drive.
  /// يبقى اختيار المظهر الأول حتى لا تُعاد شاشة المظهر بعد اكتمال الإعداد.
  Future<void> replaceLocalDataForAccountSwitch() async {
    final prefs = await AppPrefs.instance;
    final firstLaunch = prefs.getBool('first_launch');
    final hasDarkMode = prefs.containsKey('dark_mode');
    final darkMode = prefs.getBool('dark_mode');

    await ProfilePhoto.clear();
    await _clearRestorableData();

    if (firstLaunch != null) {
      await prefs.setBool('first_launch', firstLaunch);
    }
    if (hasDarkMode && darkMode != null) {
      await prefs.setBool('dark_mode', darkMode);
    }
  }

  /// متابعة بدون حساب. كل شيء يبقى محلياً ولا يُزامَن.
  Future<void> continueAsGuest() async {
    await AuthSession.instance.clearSession();

    final prefs = await AppPrefs.instance;
    await prefs.setBool(authChoiceKey, true);
  }

  /// فصل Google Drive فقط. لا يمس جلسة JWT لحساب وفّر.
  Future<void> signOut() async {
    _debounceTimer?.cancel();
    _cachedFileId = null;

    await GoogleAuthService.instance.signOut();

    final prefs = await AppPrefs.instance;

    await prefs.setBool(linkedKey, false);
    await prefs.remove(linkedEmailKey);
    await prefs.remove(linkedPhotoKey);
    await prefs.remove(restorePendingKey);
  }

  /// حذف بيانات حساب وفّر الحالي من الجهاز ومن Drive إن أمكن.
  Future<void> deleteAccount() async {
    _debounceTimer?.cancel();

    final auth = GoogleAuthService.instance;
    final email = auth.email ?? (await linkedEmail());

    if (driveBackupEnabled) {
      final headers = await auth.authHeaders(promptIfNecessary: true);

      if (headers != null) {
        var fileId = _cachedFileId;

        if (fileId == null) {
          final lookup = await DriveBackupClient.lookupBackup(headers);
          fileId = lookup.fileId;
        }

        if (fileId != null) {
          await DriveBackupClient.deleteBackup(headers, fileId);
        }
      }

      await auth.disconnect();
    }

    _cachedFileId = null;

    final prefs = await AppPrefs.instance;

    if (email != null && email.isNotEmpty) {
      await _removeAccount(prefs, email);
    }

    await prefs.setBool(linkedKey, false);
    await prefs.remove(linkedEmailKey);
    await prefs.remove(linkedPhotoKey);
    await prefs.remove(restorePendingKey);
    await prefs.setBool(authChoiceKey, true);

    await AuthSession.instance.clearSession();
    await AuthSession.instance.clearDataOwner();
    await ProfilePhoto.clear();
    await _clearRestorableData();
    _notifyRestored();
  }

  /// Updates the display name locally and marks settings dirty for sync.
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final prefs = await AppPrefs.instance;
    await prefs.setString('user_name', trimmed);

    final email = prefs.getString(linkedEmailKey);
    if (email != null && email.isNotEmpty) {
      final accounts = await _readAccounts(prefs);
      final index = accounts.indexWhere((item) => item.email == email);
      if (index >= 0) {
        accounts[index] = accounts[index].copyWith(localName: trimmed);
        await _writeAccounts(prefs, accounts);
      }
    }

    scheduleBackup();
    await SyncDirty.mark(settings: true);
  }

  Future<List<LinkedGoogleAccount>> linkedAccounts() async {
    final prefs = await AppPrefs.instance;
    return _readAccounts(prefs);
  }

  Future<String?> linkedPhotoUrl() async {
    final live = GoogleAuthService.instance.photoUrl;
    if (live != null && live.isNotEmpty) return live;

    final prefs = await AppPrefs.instance;
    return prefs.getString(linkedPhotoKey);
  }

  /// هل الجهاز مرتبط بحساب Google حالياً.
  Future<bool> isLinked() async {
    final prefs = await AppPrefs.instance;

    return prefs.getBool(linkedKey) ?? false;
  }

  /// بريد الحساب المرتبط، أو `null` في وضع الضيف.
  Future<String?> linkedEmail() async {
    final prefs = await AppPrefs.instance;

    return prefs.getString(linkedEmailKey);
  }

  // ==========================================
  // الرفع
  // ==========================================

  Future<bool> _uploadNow() async {
    if (!driveBackupEnabled) return false;

    if (_uploading) {
      _pending = true;
      return false;
    }

    _uploading = true;
    var success = false;

    try {
      final prefs = await AppPrefs.instance;

      if (!(prefs.getBool(linkedKey) ?? false)) {
        return false;
      }

      if (prefs.getBool(restorePendingKey) ?? false) {
        if (!await _completePendingRestore()) {
          return false;
        }
      }

      final auth = GoogleAuthService.instance;

      if (!auth.isSignedIn) {
        if (await auth.restoreSession() == null) {
          return false;
        }
      }

      final headers = await auth.authHeaders();

      if (headers == null) {
        return false;
      }

      if (_cachedFileId == null) {
        final lookup = await DriveBackupClient.lookupBackup(headers);

        if (lookup.failed) {
          return false;
        }

        _cachedFileId = lookup.fileId;
      }

      final content = _encodeSnapshot(prefs);

      final uploadedId = await DriveBackupClient.uploadBackup(
        headers,
        content,
        fileId: _cachedFileId,
      );

      if (uploadedId != null) {
        _cachedFileId = uploadedId;
        success = true;
      } else if (_cachedFileId != null) {
        _cachedFileId = null;
      }
    } catch (_) {
      success = false;
    } finally {
      _uploading = false;

      if (_pending) {
        _pending = false;
        scheduleBackup();
      }
    }

    return success;
  }

  /// يحاول حسم الاستعادة المؤجلة دون رفع أي شيء فوق نسخة موجودة.
  ///
  /// يرجع `true` إذا حُسم الأمر (وُجدت نسخة أو تأكد عدم وجودها).
  Future<bool> _completePendingRestore() async {
    final auth = GoogleAuthService.instance;

    if (!auth.isSignedIn) {
      if (await auth.restoreSession() == null) {
        return false;
      }
    }

    final headers = await auth.authHeaders();

    if (headers == null) {
      return false;
    }

    final lookup = await DriveBackupClient.lookupBackup(headers);

    if (lookup.failed) {
      return false;
    }

    var restored = false;

    if (lookup.exists) {
      _cachedFileId = lookup.fileId;

      final content = await DriveBackupClient.downloadBackup(
        headers,
        lookup.fileId!,
      );

      if (content != null) {
        restored = await _restoreFromJson(content);
      }
    }

    final prefs = await AppPrefs.instance;

    await prefs.setBool(restorePendingKey, false);

    if (restored) {
      _notifyRestored();
    }

    return true;
  }

  void _notifyRestored() {
    for (final listener in List<VoidCallback>.from(_restoreListeners)) {
      listener();
    }
  }

  // ==========================================
  // الترميز والاستعادة
  // ==========================================

  String _encodeSnapshot(SharedPreferences prefs) {
    final entries = <String, dynamic>{};

    for (final key in prefs.getKeys()) {
      if (_localOnlyKeys.contains(key)) {
        continue;
      }

      final value = prefs.get(key);

      final encoded = _encodeValue(value);

      if (encoded != null) {
        entries[key] = encoded;
      }
    }

    return jsonEncode(<String, dynamic>{
      'version': _schemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'entries': entries,
    });
  }

  /// النوع يُحفظ صراحة لأن JSON لا يميّز `int` عن `double`.
  Map<String, dynamic>? _encodeValue(Object? value) {
    if (value is bool) {
      return <String, dynamic>{'t': 'b', 'v': value};
    }

    if (value is int) {
      return <String, dynamic>{'t': 'i', 'v': value};
    }

    if (value is double) {
      return <String, dynamic>{'t': 'd', 'v': value};
    }

    if (value is String) {
      return <String, dynamic>{'t': 's', 'v': value};
    }

    if (value is List<String>) {
      return <String, dynamic>{'t': 'sl', 'v': value};
    }

    if (value is List) {
      return <String, dynamic>{
        't': 'sl',
        'v': value.map((item) => item.toString()).toList(),
      };
    }

    return null;
  }

  Future<bool> _restoreFromJson(
    String content, {
    bool replaceExisting = false,
  }) async {
    Map<String, dynamic> entries;

    try {
      final decoded = jsonDecode(content);

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final raw = decoded['entries'];

      if (raw is! Map<String, dynamic> || raw.isEmpty) {
        return false;
      }

      entries = raw;
    } catch (_) {
      return false;
    }

    _restoring = true;

    try {
      final prefs = await AppPrefs.instance;

      if (replaceExisting) {
        await _clearRestorablePrefs(prefs);
      }

      var written = 0;

      for (final entry in entries.entries) {
        if (_localOnlyKeys.contains(entry.key)) {
          continue;
        }

        if (await _writeValue(prefs, entry.key, entry.value)) {
          written++;
        }
      }

      if (written == 0) {
        return false;
      }

      await _reloadStores();

      return true;
    } catch (_) {
      return false;
    } finally {
      _restoring = false;
    }
  }

  Future<bool> _writeValue(
    SharedPreferences prefs,
    String key,
    Object? encoded,
  ) async {
    if (encoded is! Map) {
      return false;
    }

    final type = encoded['t'];
    final value = encoded['v'];

    try {
      switch (type) {
        case 'b':
          if (value is! bool) return false;
          return await prefs.setBool(key, value);

        case 'i':
          if (value is! int) return false;
          return await prefs.setInt(key, value);

        case 'd':
          if (value is! num) return false;
          return await prefs.setDouble(key, value.toDouble());

        case 's':
          if (value is! String) return false;
          return await prefs.setString(key, value);

        case 'sl':
          if (value is! List) return false;
          return await prefs.setStringList(
            key,
            value.map((item) => item.toString()).toList(),
          );

        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// بعد الاستعادة يجب أن تقرأ المخازن الحية القيم الجديدة.
  Future<void> _reloadStores() async {
    TransactionStore.instance.resetCache();
    CurrencyStore.instance.resetCache();
    NotificationService.instance.resetCache();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();

    await Future.wait<void>(<Future<void>>[
      CurrencyStore.instance.ensureLoaded(),
      TransactionStore.instance.ensureLoaded(),
      NotificationService.instance.ensureLoaded(),
      ShoppingListStore.instance.ensureLoaded(),
      RecurringExpenseStore.instance.ensureLoaded(),
      CategoryStore.instance.ensureLoaded(),
    ]);

    await RecurringExpenseStore.instance.processDue();
  }

  Future<void> _clearRestorableData() async {
    final prefs = await AppPrefs.instance;
    await _clearRestorablePrefs(prefs);
    await _reloadStores();
  }

  Future<void> _clearRestorablePrefs(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().toList()) {
      if (_localOnlyKeys.contains(key)) continue;
      await prefs.remove(key);
    }
  }

  Future<void> _markLinked(
    String email, {
    required bool restorePending,
  }) async {
    final prefs = await AppPrefs.instance;
    final auth = GoogleAuthService.instance;

    await prefs.setBool(authChoiceKey, true);
    await prefs.setBool(linkedKey, true);
    await prefs.setString(linkedEmailKey, email);
    await prefs.setBool(restorePendingKey, restorePending);

    final photo = auth.photoUrl;
    if (photo != null && photo.isNotEmpty) {
      await prefs.setString(linkedPhotoKey, photo);
    }

    final userName = prefs.getString('user_name') ?? '';
    if (userName.isEmpty) {
      final googleName = auth.displayName?.trim() ?? '';
      if (googleName.isNotEmpty) {
        await prefs.setString('user_name', googleName);
      }
    }

    final userEmail = prefs.getString('user_email') ?? '';
    if (userEmail.isEmpty) {
      await prefs.setString('user_email', email);
    }

    await _upsertAccount(
      prefs,
      LinkedGoogleAccount(
        email: email,
        googleName: auth.displayName ?? '',
        photoUrl: photo,
        localName: prefs.getString('user_name'),
      ),
    );
  }

  Future<List<LinkedGoogleAccount>> _readAccounts(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(accountsKey);
    if (raw == null || raw.isEmpty) {
      final email = prefs.getString(linkedEmailKey);
      if (email == null || email.isEmpty) return const [];

      return [
        LinkedGoogleAccount(
          email: email,
          googleName: prefs.getString('user_name') ?? '',
          photoUrl: prefs.getString(linkedPhotoKey),
          localName: prefs.getString('user_name'),
        ),
      ];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      return decoded
          .map(LinkedGoogleAccount.fromJson)
          .whereType<LinkedGoogleAccount>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeAccounts(
    SharedPreferences prefs,
    List<LinkedGoogleAccount> accounts,
  ) async {
    await prefs.setString(
      accountsKey,
      jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _upsertAccount(
    SharedPreferences prefs,
    LinkedGoogleAccount account,
  ) async {
    final accounts = await _readAccounts(prefs);
    final index = accounts.indexWhere((item) => item.email == account.email);

    if (index >= 0) {
      final existing = accounts[index];
      accounts[index] = existing.copyWith(
        googleName: account.googleName,
        photoUrl: account.photoUrl,
        localName: account.localName ?? existing.localName,
      );
    } else {
      accounts.add(account);
    }

    await _writeAccounts(prefs, accounts);
  }

  Future<void> _removeAccount(SharedPreferences prefs, String email) async {
    final accounts = await _readAccounts(prefs)
      ..removeWhere((item) => item.email == email);
    await _writeAccounts(prefs, accounts);
  }

  void _attachListeners() {
    if (_listenersAttached) {
      return;
    }

    _listenersAttached = true;

    TransactionStore.instance.addListener(scheduleBackup);
    NotificationService.instance.addListener(scheduleBackup);
    ShoppingListStore.instance.addListener(scheduleBackup);
    RecurringExpenseStore.instance.addListener(scheduleBackup);
    CategoryStore.instance.addListener(scheduleBackup);
  }
}
