import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/data/stores/expense_preset_store.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/sync/api_config.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

/// Local account data on this device: the guest choice, the display name,
/// and wiping data when the account is deleted or switched. Cloud copies go
/// through the Waffr API (SyncService); there is no Google sign-in.
class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  /// مفتاح يدل على أن المستخدم تجاوز شاشة الدخول
  /// (سواء بحساب أو كضيف).
  static const String authChoiceKey = 'auth_choice_made';

  /// مفاتيح تصف حالة هذا الجهاز وجلسته، فلا تُمسح مع بيانات المستخدم.
  static const Set<String> _localOnlyKeys = <String>{
    authChoiceKey,
    AuthSession.tokenKey,
    AuthSession.lastSyncKey,
    AuthSession.accountEmailKey,
    AuthSession.dataOwnerKey,
    AuthSession.legacyPasswordKey,
    ApiConfig.overrideKey,
  };

  final List<VoidCallback> _resetListeners = <VoidCallback>[];

  /// يُستدعى بعد مسح بيانات الجهاز بينما التطبيق يعمل،
  /// حتى يعيد مسار الإقلاع قراءة الحالة.
  void addRestoreListener(VoidCallback listener) {
    _resetListeners.add(listener);
  }

  void removeRestoreListener(VoidCallback listener) {
    _resetListeners.remove(listener);
  }

  /// يمسح البيانات المحلية القابلة للمزامنة قبل حساب آخر.
  /// يبقى اختيار المظهر الأول حتى لا تُعاد شاشة المظهر بعد اكتمال الإعداد.
  Future<void> replaceLocalDataForAccountSwitch() async {
    await _clearUserDataKeepingTheme();
  }

  /// متابعة بدون حساب. كل شيء يبقى محلياً ولا يُزامَن.
  Future<void> continueAsGuest() async {
    await AuthSession.instance.clearSession();

    final prefs = await AppPrefs.instance;
    await prefs.setBool(authChoiceKey, true);
  }

  /// حذف بيانات حساب وفّر الحالي من هذا الجهاز.
  Future<void> deleteAccount() async {
    final prefs = await AppPrefs.instance;
    await prefs.setBool(authChoiceKey, true);

    await AuthSession.instance.clearSession();
    await AuthSession.instance.clearDataOwner();
    // Keep the light/dark choice: the app is still open in that theme, and
    // wiping it would flip to the system theme and reopen the theme picker.
    await _clearUserDataKeepingTheme();
    _notifyReset();
  }

  /// Updates the display name locally and marks settings dirty for sync.
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final prefs = await AppPrefs.instance;
    await prefs.setString('user_name', trimmed);
    await SyncDirty.mark(settings: true);
  }

  void _notifyReset() {
    for (final listener in List<VoidCallback>.from(_resetListeners)) {
      listener();
    }
  }

  /// بعد المسح يجب أن تقرأ المخازن الحية القيم الجديدة.
  Future<void> _reloadStores() async {
    TransactionStore.instance.resetCache();
    CurrencyStore.instance.resetCache();
    NotificationService.instance.resetCache();
    UsageStreakService.instance.resetCache();
    ProfileIdentity.instance.reset();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();
    ExpensePresetStore.instance.resetCache();

    await Future.wait<void>(<Future<void>>[
      CurrencyStore.instance.ensureLoaded(),
      TransactionStore.instance.ensureLoaded(),
      NotificationService.instance.ensureLoaded(),
      UsageStreakService.instance.ensureLoaded(),
      ShoppingListStore.instance.ensureLoaded(),
      RecurringExpenseStore.instance.ensureLoaded(),
      CategoryStore.instance.ensureLoaded(),
    ]);

    await RecurringExpenseStore.instance.processDue();
  }

  /// Clears user data but restores the first-launch flag and the light/dark
  /// choice, which describe this device rather than the account.
  Future<void> _clearUserDataKeepingTheme() async {
    final prefs = await AppPrefs.instance;
    final firstLaunch = prefs.getBool('first_launch');
    final darkMode = prefs.getBool('dark_mode');

    await _clearUserData();

    if (firstLaunch != null) {
      await prefs.setBool('first_launch', firstLaunch);
    }
    if (darkMode != null) {
      await prefs.setBool('dark_mode', darkMode);
    }
  }

  Future<void> _clearUserData() async {
    final prefs = await AppPrefs.instance;
    await _clearUserPrefs(prefs);
    await _reloadStores();
  }

  Future<void> _clearUserPrefs(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().toList()) {
      if (_localOnlyKeys.contains(key)) continue;
      await prefs.remove(key);
    }
  }
}
