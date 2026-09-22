import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';

enum AppLockToggleResult { enabled, disabled, unsupported, cancelled }

class AppLock {
  AppLock._();

  static const prefsKey = 'app_lock';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  static Future<AppLockToggleResult> setEnabled({
    required bool enabled,
    required LocalAuthentication auth,
    String reason = 'تفعيل قفل التطبيق',
    void Function()? onEnabled,
    void Function()? onDisabled,
  }) async {
    if (!enabled) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, false);
      BackupService.instance.scheduleBackup();
      onDisabled?.call();
      return AppLockToggleResult.disabled;
    }

    final supported = await auth.isDeviceSupported();
    if (!supported) {
      return AppLockToggleResult.unsupported;
    }

    try {
      final authenticated = await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );

      if (!authenticated) {
        return AppLockToggleResult.cancelled;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, true);
      BackupService.instance.scheduleBackup();
      onEnabled?.call();
      return AppLockToggleResult.enabled;
    } on LocalAuthException {
      return AppLockToggleResult.cancelled;
    } catch (_) {
      return AppLockToggleResult.cancelled;
    }
  }
}
