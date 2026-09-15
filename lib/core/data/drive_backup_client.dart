import 'dart:convert';

import 'package:http/http.dart' as http;

/// نتيجة البحث عن ملف النسخة الاحتياطية.
///
/// التمييز بين «لا يوجد ملف» و«فشل الاتصال» ضروري حتى لا
/// يُنشأ ملف جديد يطغى على نسخة موجودة عندما تكون الشبكة مقطوعة.
class DriveBackupLookup {
  const DriveBackupLookup._(this.fileId, this.failed);

  const DriveBackupLookup.found(String id) : this._(id, false);

  const DriveBackupLookup.missing() : this._(null, false);

  const DriveBackupLookup.failed() : this._(null, true);

  final String? fileId;
  final bool failed;

  bool get exists => fileId != null && fileId!.isNotEmpty;
}

/// عميل مبسّط لـ Google Drive يعمل داخل مجلد بيانات التطبيق
/// المخفي (`appDataFolder`) فقط.
///
/// كل الدوال تفشل بصمت، لأن المزامنة انتهازية ويجب ألّا توقف التطبيق.
class DriveBackupClient {
  DriveBackupClient._();

  static const String backupFileName = 'waffer_backup.json';

  static const String _filesEndpoint =
      'https://www.googleapis.com/drive/v3/files';

  static const String _uploadEndpoint =
      'https://www.googleapis.com/upload/drive/v3/files';

  static const Duration _timeout = Duration(seconds: 20);

  /// يبحث عن ملف النسخة الاحتياطية في مجلد بيانات التطبيق.
  static Future<DriveBackupLookup> lookupBackup(
    Map<String, String> headers,
  ) async {
    final uri = Uri.parse(_filesEndpoint).replace(
      queryParameters: <String, String>{
        'spaces': 'appDataFolder',
        'q': "name = '$backupFileName' and trashed = false",
        'fields': 'files(id)',
        'pageSize': '1',
      },
    );

    try {
      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode != 200) {
        return const DriveBackupLookup.failed();
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return const DriveBackupLookup.failed();
      }

      final files = decoded['files'];

      if (files is! List || files.isEmpty) {
        return const DriveBackupLookup.missing();
      }

      final first = files.first;

      if (first is! Map<String, dynamic>) {
        return const DriveBackupLookup.missing();
      }

      final id = first['id'];

      if (id is String && id.isNotEmpty) {
        return DriveBackupLookup.found(id);
      }

      return const DriveBackupLookup.missing();
    } catch (_) {
      return const DriveBackupLookup.failed();
    }
  }

  /// يقرأ محتوى ملف النسخة الاحتياطية نصاً.
  static Future<String?> downloadBackup(
    Map<String, String> headers,
    String fileId,
  ) async {
    final uri = Uri.parse('$_filesEndpoint/$fileId').replace(
      queryParameters: <String, String>{'alt': 'media'},
    );

    try {
      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      // Drive لا يضبط الترميز دائماً، لذا نفكّ البايتات يدوياً.
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  /// ينشئ الملف أو يستبدل محتواه.
  ///
  /// يرجع معرّف الملف عند النجاح، أو `null` عند الفشل.
  static Future<String?> uploadBackup(
    Map<String, String> headers,
    String content, {
    String? fileId,
  }) {
    return fileId == null
        ? _createBackup(headers, content)
        : _updateBackup(headers, fileId, content);
  }

  static Future<String?> _createBackup(
    Map<String, String> headers,
    String content,
  ) async {
    const boundary = 'waffer-backup-boundary';

    final metadata = jsonEncode(<String, dynamic>{
      'name': backupFileName,
      'parents': <String>['appDataFolder'],
    });

    final body = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$content\r\n'
      '--$boundary--',
    );

    final uri = Uri.parse(_uploadEndpoint).replace(
      queryParameters: <String, String>{
        'uploadType': 'multipart',
        'fields': 'id',
      },
    );

    try {
      final response = await http
          .post(
            uri,
            headers: <String, String>{
              ...headers,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final id = decoded['id'];

      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _updateBackup(
    Map<String, String> headers,
    String fileId,
    String content,
  ) async {
    final uri = Uri.parse('$_uploadEndpoint/$fileId').replace(
      queryParameters: <String, String>{
        'uploadType': 'media',
        'fields': 'id',
      },
    );

    try {
      final response = await http
          .patch(
            uri,
            headers: <String, String>{
              ...headers,
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: utf8.encode(content),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      return fileId;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> deleteBackup(
    Map<String, String> headers,
    String fileId,
  ) async {
    final uri = Uri.parse('$_filesEndpoint/$fileId');

    try {
      final response = await http
          .delete(uri, headers: headers)
          .timeout(_timeout);

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
