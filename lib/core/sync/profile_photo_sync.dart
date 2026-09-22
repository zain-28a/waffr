// Uploads and downloads the profile photo via /auth/photo, separate from /sync.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:waffer/data/services/profile_photo.dart';
import 'package:waffer/core/sync/api_config.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_clock.dart';

// Keeps the on-device avatar in sync with the account photo endpoint.
class ProfilePhotoSync {
  ProfilePhotoSync._();

  static const Duration _timeout = Duration(seconds: 25);

  // After flushing pending local photo actions, pull or clear from settings.
  static Future<void> applyFromSettings(Map<String, dynamic>? settings) async {
    await flush();
    if (settings == null) return;
    if (await ProfilePhoto.pendingAction() != null) return;

    final hasPhoto = settings['has_photo'] == true;
    final remoteUpdated = parseSyncDate(settings['photo_updated_at']);
    final localUpdated = await ProfilePhoto.updatedAt();
    final localPath = await ProfilePhoto.path();

    if (hasPhoto) {
      final alreadyCurrent = localPath != null &&
          remoteUpdated != null &&
          localUpdated != null &&
          !remoteUpdated.isAfter(localUpdated);
      if (alreadyCurrent) return;
      final downloaded = await download();
      if (downloaded) {
        await ProfilePhoto.setUpdatedAt(remoteUpdated ?? syncNow());
      }
      return;
    }

    if (remoteUpdated != null) {
      if (localUpdated != null && remoteUpdated.isBefore(localUpdated)) {
        return;
      }
      await ProfilePhoto.clear();
      await ProfilePhoto.setUpdatedAt(remoteUpdated);
      return;
    }

    if (localPath != null) {
      await ProfilePhoto.markPending(ProfilePhoto.pendingUpload);
      await flush();
    }
  }

  // Run any pending upload or remote delete before the next sync continues.
  static Future<void> flush() async {
    final pending = await ProfilePhoto.pendingAction();
    if (pending == ProfilePhoto.pendingUpload) {
      await uploadCurrent();
    } else if (pending == ProfilePhoto.pendingDelete) {
      await deleteRemote();
    }
  }

  static Future<bool> uploadCurrent() async {
    final path = await ProfilePhoto.path();
    if (path == null) {
      await ProfilePhoto.clearPending();
      return true;
    }

    final token = await AuthSession.instance.token();
    if (token == null) return false;

    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return false;

      final base = await ApiConfig.baseUrl();
      final response = await http
          .put(
            Uri.parse('$base/auth/photo'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        await AuthSession.instance.clearSession();
        return false;
      }
      if (response.statusCode != 200) return false;

      await ProfilePhoto.clearPending();
      await _storeRemoteUpdated(response);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> download() async {
    final token = await AuthSession.instance.token();
    if (token == null) return false;

    try {
      final base = await ApiConfig.baseUrl();
      final response = await http
          .get(
            Uri.parse('$base/auth/photo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);

      if (response.statusCode == 404) {
        await ProfilePhoto.clear();
        return true;
      }
      if (response.statusCode == 401) {
        await AuthSession.instance.clearSession();
        return false;
      }
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }

      await ProfilePhoto.saveBytes(response.bodyBytes);
      await ProfilePhoto.clearPending();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteRemote() async {
    final token = await AuthSession.instance.token();
    if (token == null) return false;

    try {
      final base = await ApiConfig.baseUrl();
      final response = await http
          .delete(
            Uri.parse('$base/auth/photo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        await AuthSession.instance.clearSession();
        return false;
      }
      if (response.statusCode != 200) return false;

      await ProfilePhoto.clearPending();
      await _storeRemoteUpdated(response);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _storeRemoteUpdated(http.Response response) async {
    try {
      if (response.body.isEmpty) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final parsed = parseSyncDate(decoded['photo_updated_at']);
      if (parsed != null) {
        await ProfilePhoto.setUpdatedAt(parsed);
      }
    } catch (_) {}
  }
}
