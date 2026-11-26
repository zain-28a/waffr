// LedgerBackupCodec: the encrypted backup file round-trips, refuses a wrong
// passphrase, a changed file and files it cannot read, and shows nothing
// private outside the sealed part.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/ledger_backup_codec.dart';

const _fast = LedgerBackupCodec.minIterations;

final Map<String, dynamic> _body = {
  'snapshot': {
    'transactions': {
      'upserts': [
        {'client_id': 't1', 'amount': '12500', 'note': 'إيجار الشقة'},
      ],
    },
  },
  'account_email': 'owner@example.com',
};

Future<Uint8List> _seal({String passphrase = 'correct horse battery'}) =>
    LedgerBackupCodec.seal(
      body: _body,
      passphrase: passphrase,
      iterations: _fast,
    );

Map<String, dynamic> _json(Uint8List file) =>
    Map<String, dynamic>.from(jsonDecode(utf8.decode(file)) as Map);

Uint8List _bytes(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  test('a sealed file opens with its passphrase', () async {
    final file = await _seal();
    final opened = await LedgerBackupCodec.open(
      file: file,
      passphrase: 'correct horse battery',
    );
    expect(opened, _body);
  });

  test('nothing private is readable outside the sealed part', () async {
    final text = utf8.decode(await _seal());
    expect(text, isNot(contains('12500')));
    expect(text, isNot(contains('owner@example.com')));
    expect(text, isNot(contains('t1')));
    final json = jsonDecode(text) as Map;
    expect(json['format'], 'waffr-backup');
    expect(json['version'], 1);
    expect(json['kdf']['name'], 'pbkdf2-hmac-sha256');
    expect(json['kdf']['iterations'], _fast);
  });

  test('two files of the same data differ (fresh salt and nonce)', () async {
    final a = _json(await _seal());
    final b = _json(await _seal());
    expect(a['kdf']['salt'], isNot(b['kdf']['salt']));
    expect(a['nonce'], isNot(b['nonce']));
  });

  test('new files use 600,000 iterations by default', () {
    expect(LedgerBackupCodec.defaultIterations, 600000);
  });

  test('a wrong passphrase is refused', () async {
    final file = await _seal();
    expect(
      LedgerBackupCodec.open(file: file, passphrase: 'wrong horse battery'),
      throwsA(isA<BackupPassphraseException>()),
    );
  });

  test('a changed ciphertext is refused', () async {
    final json = _json(await _seal());
    final data = base64Decode(json['data'] as String);
    data[0] ^= 1;
    json['data'] = base64Encode(data);
    expect(
      LedgerBackupCodec.open(
        file: _bytes(json),
        passphrase: 'correct horse battery',
      ),
      throwsA(isA<BackupPassphraseException>()),
    );
  });

  test('a changed header is refused (it is bound to the ciphertext)', () async {
    final json = _json(await _seal());
    json['created_at'] = '2020-01-01T00:00:00.000Z';
    expect(
      LedgerBackupCodec.open(
        file: _bytes(json),
        passphrase: 'correct horse battery',
      ),
      throwsA(isA<BackupPassphraseException>()),
    );
  });

  test('lowering the iterations in the header does not help', () async {
    final json = _json(
      await LedgerBackupCodec.seal(
        body: _body,
        passphrase: 'correct horse battery',
        iterations: _fast + 1,
      ),
    );
    json['kdf']['iterations'] = _fast;
    expect(
      LedgerBackupCodec.open(
        file: _bytes(json),
        passphrase: 'correct horse battery',
      ),
      throwsA(isA<BackupPassphraseException>()),
    );
  });

  group('files that are not readable backups', () {
    Future<void> refused(Uint8List file) => expectLater(
      LedgerBackupCodec.open(file: file, passphrase: 'correct horse battery'),
      throwsA(isA<BackupFormatException>()),
    );

    test('empty or not JSON', () async {
      await refused(Uint8List(0));
      await refused(Uint8List.fromList(utf8.encode('%PDF-1.7')));
    });

    test('another JSON file', () async {
      await refused(_bytes({'hello': 'world'}));
    });

    test('a newer format version', () async {
      final json = _json(await _seal())..['version'] = 2;
      await refused(_bytes(json));
    });

    test('iterations out of bounds (weak or a freeze)', () async {
      final weak = _json(await _seal());
      weak['kdf']['iterations'] = 1000;
      await refused(_bytes(weak));
      final huge = _json(await _seal());
      huge['kdf']['iterations'] = 1000000000;
      await refused(_bytes(huge));
    });

    test('an unknown algorithm', () async {
      final json = _json(await _seal())..['cipher'] = 'aes-128-cbc';
      await refused(_bytes(json));
    });

    test('a file over the size limit', () async {
      await refused(Uint8List(LedgerBackupCodec.maxFileBytes + 1));
    });
  });
}
