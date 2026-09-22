import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:waffer/core/sync/sync_clock.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

/// Local profile photo file plus prefs for path, sync time, and pending action.
class ProfilePhoto {
  ProfilePhoto._();

  static const String prefsKey = 'user_photo_path';
  static const String updatedAtKey = 'user_photo_updated_at';
  static const String pendingKey = 'user_photo_pending';

  static const String pendingUpload = 'upload';
  static const String pendingDelete = 'delete';

  static Future<String> _destPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/waffer_profile_photo.jpg';
  }

  /// Returns the stored path if the file still exists; otherwise clears prefs.
  static Future<String?> path() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getString(prefsKey)?.trim() ?? '';
    if (stored.isEmpty) return null;
    if (!File(stored).existsSync()) {
      await prefs.remove(prefsKey);
      return null;
    }
    return stored;
  }

  static Future<DateTime?> updatedAt() async {
    final prefs = await AppPrefs.instance;
    return parseSyncDate(prefs.getString(updatedAtKey));
  }

  static Future<void> setUpdatedAt(DateTime? value) async {
    final prefs = await AppPrefs.instance;
    if (value == null) {
      await prefs.remove(updatedAtKey);
      return;
    }
    await prefs.setString(updatedAtKey, toSyncIso(value));
  }

  /// Pending sync action (`upload` / `delete`), or null if none.
  static Future<String?> pendingAction() async {
    final prefs = await AppPrefs.instance;
    final value = prefs.getString(pendingKey)?.trim() ?? '';
    if (value == pendingUpload || value == pendingDelete) return value;
    return null;
  }

  /// Queues a sync action and bumps [updatedAtKey] to now.
  static Future<void> markPending(String action) async {
    final prefs = await AppPrefs.instance;
    await prefs.setString(pendingKey, action);
    await prefs.setString(updatedAtKey, toSyncIso(syncNow()));
  }

  static Future<void> clearPending() async {
    final prefs = await AppPrefs.instance;
    await prefs.remove(pendingKey);
  }

  /// Writes image bytes to the canonical documents path and stores that path.
  static Future<String> saveBytes(List<int> bytes) async {
    final dest = File(await _destPath());
    if (await dest.exists()) {
      await dest.delete();
    }
    await dest.writeAsBytes(bytes, flush: true);

    final prefs = await AppPrefs.instance;
    await prefs.setString(prefsKey, dest.path);
    return dest.path;
  }

  /// Picks/resizes an image, copies it locally, and marks upload pending.
  static Future<String?> pick({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (picked == null) return await path();

      final dest = File(await _destPath());
      if (await dest.exists()) {
        await dest.delete();
      }
      await File(picked.path).copy(dest.path);

      final prefs = await AppPrefs.instance;
      await prefs.setString(prefsKey, dest.path);
      await markPending(pendingUpload);
      return dest.path;
    } catch (_) {
      return await path();
    }
  }

  /// Deletes the local file; [rememberDelete] queues a server delete for sync.
  static Future<void> clear({bool rememberDelete = false}) async {
    final current = await path();
    if (current != null) {
      final file = File(current);
      if (await file.exists()) {
        await file.delete();
      }
    }
    final prefs = await AppPrefs.instance;
    await prefs.remove(prefsKey);
    if (rememberDelete) {
      await markPending(pendingDelete);
    } else {
      await prefs.remove(pendingKey);
      await prefs.remove(updatedAtKey);
    }
  }
}
