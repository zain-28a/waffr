// Guards the Android backup rules: only the ledger prefs may leave the phone,
// cloud backups only when end-to-end encrypted, and never the secure-storage
// files (token and data key) or the widget prefs.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const res = 'android/app/src/main/res/xml';

  test('the manifest points at both rule files', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest, isNot(contains('android:allowBackup="true"')));
  });

  test('Android 12+: cloud backup only with end-to-end encryption', () {
    final rules = _read('$res/data_extraction_rules.xml');
    expect(
      rules,
      contains('<cloud-backup disableIfNoEncryptionCapabilities="true">'),
    );
    expect(rules, contains('<device-transfer>'));
  });

  test('Android 11 and earlier: only with client-side encryption', () {
    final rules = _read('$res/backup_rules.xml');
    expect(rules, contains('requireFlags="clientSideEncryption"'));
  });

  for (final file in ['data_extraction_rules.xml', 'backup_rules.xml']) {
    test('$file includes the ledger prefs and nothing else', () {
      final rules = _read('$res/$file');
      final includes = RegExp(r'<include\b[^>]*path="([^"]+)"')
          .allMatches(rules)
          .map((match) => match.group(1))
          .toSet();
      expect(includes, {'FlutterSharedPreferences.xml'});
      expect(rules, isNot(contains('domain="root"')));
      expect(rules, isNot(contains('domain="file"')));
      expect(rules, isNot(contains('domain="database"')));
    });
  }
}
