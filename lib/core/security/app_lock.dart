// Biometric / device-credential app lock toggle backed by SharedPreferences.

import 'package:local_auth/local_auth.dart';
import 'package:waffr/data/services/backup_service.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

enum AppLockToggleResult { enabled, disabled, unsupported, cancelled }

// Enable or disable requiring authentication when the app opens.
class AppLock {
  AppLock._();

  static const prefsKey = 'app_lock';

  static Future<bool> isEnabled() async {
    final prefs = await AppPrefs.instance;
    return prefs.getBool(prefsKey) ?? false;
  }

  // Turning on prompts the OS authenticator first; turning off just clears the flag.
  static Future<AppLockToggleResult> setEnabled({
    required bool enabled,
    required LocalAuthentication auth,
    String reason = 'تفعيل قفل التطبيق',
    void Function()? onEnabled,
    void Function()? onDisabled,
  }) async {
    if (!enabled) {
      final prefs = await AppPrefs.instance;
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
    } on LocalAuthException {
      return AppLockToggleResult.cancelled;
    } catch (_) {
      return AppLockToggleResult.cancelled;
    }

    final prefs = await AppPrefs.instance;
    await prefs.setBool(prefsKey, true);
    BackupService.instance.scheduleBackup();
    onEnabled?.call();
    return AppLockToggleResult.enabled;
  }
}
