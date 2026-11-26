// Release A compatibility: what users already have stays readable, whichever
// implementation derives the key.
//
// test/fixtures/crypto_compat.json is made by Python (hashlib PBKDF2 and
// pyca/cryptography AES-GCM, tool/gen_crypto_compat_fixture.py), so it stands
// in for wraps and backup files created by earlier app versions without
// depending on this code. Every case runs through three engines: Dart only
// (old builds, tests), a correct native side, and a native side that passes
// the self-test but is wrong above 4,096 iterations.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/data_key.dart';
import 'package:waffr/core/security/ledger_backup_codec.dart';
import 'package:waffr/core/security/pbkdf2.dart';

import '../../helpers/fake_native_pbkdf2.dart';

final Map<String, dynamic> _fixture = Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/crypto_compat.json').readAsStringSync())
      as Map,
);

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
];

Map<String, Pbkdf2Engine Function()> _engines() => {
  'Dart only': dartOnlyEngine,
  'correct native': () => fakeNativeEngine().engine,
  'faulty native': () =>
      fakeNativeEngine(fault: FakeNativeFault.wrongAboveSelfTest).engine,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DataKeyStore.engine = Pbkdf2Engine.instance;
    LedgerBackupCodec.engine = Pbkdf2Engine.instance;
  });

  test('new wraps keep the 210,000-iteration default (Release A)', () {
    expect(DataKeyStore.defaultIterations, 210000);
  });

  for (final entry in _engines().entries) {
    group('${entry.key}:', () {
      setUp(() {
        DataKeyStore.engine = entry.value();
        LedgerBackupCodec.engine = DataKeyStore.engine;
      });

      for (final item in (_fixture['wrapped_keys'] as List).cast<Map>()) {
        final wrapped = WrappedDataKey.fromJson(item['wrapped']);
        test(
          'an existing ${wrapped!.iterations} wrap opens (${item['password']})',
          () async {
            final key = await DataKeyStore.unwrap(
              item['password'] as String,
              wrapped,
            );
            expect(key, _hex(item['data_key_hex'] as String));
          },
          timeout: const Timeout(Duration(minutes: 2)),
        );

        test('the wrong password still opens nothing', () async {
          expect(
            await DataKeyStore.unwrap('not the password', wrapped),
            isNull,
          );
        }, timeout: const Timeout(Duration(minutes: 2)));
      }

      test('an existing backup file opens', () async {
        final backup = (_fixture['backups'] as List).first as Map;
        final body = await LedgerBackupCodec.open(
          file: Uint8List.fromList(utf8.encode(backup['file'] as String)),
          passphrase: backup['passphrase'] as String,
        );
        expect(body, backup['body']);
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('a new wrap opens through every other engine', () async {
        final key = List<int>.generate(32, (i) => 255 - i);
        final wrapped = await DataKeyStore.wrap(
          key,
          'كلمة 🔐',
          iterations: 20000,
        );
        expect(wrapped.iterations, 20000);
        for (final other in _engines().values) {
          DataKeyStore.engine = other();
          expect(await DataKeyStore.unwrap('كلمة 🔐', wrapped), key);
        }
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('a new backup file opens through every other engine', () async {
        final file = await LedgerBackupCodec.seal(
          body: {'ok': 'نعم'},
          passphrase: 'a long backup passphrase',
          iterations: LedgerBackupCodec.minIterations,
        );
        for (final other in _engines().values) {
          LedgerBackupCodec.engine = other();
          final body = await LedgerBackupCodec.open(
            file: file,
            passphrase: 'a long backup passphrase',
          );
          expect(body, {'ok': 'نعم'});
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    });
  }

  test('a native side that disagrees while writing is switched off', () async {
    final fake = fakeNativeEngine(fault: FakeNativeFault.wrongAboveSelfTest);
    DataKeyStore.engine = fake.engine;
    final wrapped = await DataKeyStore.wrap(
      List<int>.filled(32, 7),
      'pw 123456',
      iterations: 20000,
    );
    expect(fake.engine.disabledReason, 'mismatch:write');
    // What was written is the Dart key, so a Dart-only device opens it.
    DataKeyStore.engine = dartOnlyEngine();
    expect(
      await DataKeyStore.unwrap('pw 123456', wrapped),
      List<int>.filled(32, 7),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'reading uses native, and a wrong native key falls back to Dart',
    () async {
      final item = (_fixture['wrapped_keys'] as List).first as Map;
      final wrapped = WrappedDataKey.fromJson(item['wrapped'])!;
      final good = fakeNativeEngine();
      DataKeyStore.engine = good.engine;
      expect(
        await DataKeyStore.unwrap(item['password'] as String, wrapped),
        _hex(item['data_key_hex'] as String),
      );
      expect(good.native.calls.last, wrapped.iterations); // native did the work
      expect(good.native.calls.where((n) => n == wrapped.iterations).length, 1);

      final faulty = fakeNativeEngine(
        fault: FakeNativeFault.wrongAboveSelfTest,
      );
      DataKeyStore.engine = faulty.engine;
      expect(
        await DataKeyStore.unwrap(item['password'] as String, wrapped),
        _hex(item['data_key_hex'] as String),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'new wraps are written with the Dart key even when native is correct',
    () async {
      // deriveForWriting: native only checks.
      final fake = fakeNativeEngine();
      DataKeyStore.engine = fake.engine;
      await DataKeyStore.wrap(
        List<int>.filled(32, 1),
        'pw 123456',
        iterations: 20000,
      );
      expect(fake.engine.disabledReason, isNull);
      expect(fake.native.calls.last, 20000);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('the stored wrap format is unchanged', () {
    final item = (_fixture['wrapped_keys'] as List).first as Map;
    final wrapped = WrappedDataKey.fromJson(item['wrapped'])!;
    expect(wrapped.toJson(), item['wrapped']);
  });
}
