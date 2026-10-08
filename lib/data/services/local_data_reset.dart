import 'package:waffer/data/stores/expense_preset_store.dart';
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/data/services/profile_identity.dart';
import 'package:waffer/data/services/system_notifications.dart';
import 'package:waffer/data/services/usage_streak_service.dart';
import 'package:waffer/data/services/profile_photo.dart';
import 'package:waffer/data/stores/recurring_expense_store.dart';
import 'package:waffer/data/stores/shopping_list_store.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

/// Wipes Waffer data on this device only (prefs, session, photo, store caches).
class LocalDataReset {
  LocalDataReset._();

  /// Clears prefs/session/photo, then resets every in-memory store cache.
  static Future<void> resetCurrentDevice() async {
    final prefs = await AppPrefs.instance;

    await prefs.clear();
    await AuthSession.instance.clearSession();
    await AuthSession.instance.clearDataOwner();
    await ProfilePhoto.clear();

    TransactionStore.instance.resetCache();
    CurrencyStore.instance.resetCache();
    NotificationService.instance.resetCache();
    UsageStreakService.instance.resetCache();
    ProfileIdentity.instance.reset();
    await SystemNotifications.instance.cancelAll();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();
    ExpensePresetStore.instance.resetCache();
  }
}
