import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/category_store.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/profile_photo.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/shopping_list_store.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/sync/auth_session.dart';

/// Clears Waffer data stored on the current device only.
class LocalDataReset {
  LocalDataReset._();

  static Future<void> resetCurrentDevice() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.clear();
    await AuthSession.instance.clearSession();
    await AuthSession.instance.clearDataOwner();
    await ProfilePhoto.clear();

    TransactionStore.instance.resetCache();
    NotificationService.instance.resetCache();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();
  }
}
