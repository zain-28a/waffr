// The encrypted backup file format: a small JSON header and the ledger
// snapshot, gzipped and sealed with AES-256-GCM under a key derived from a
// passphrase the user chooses (PBKDF2-HMAC-SHA256).
//
// File (UTF-8 JSON):
//   {
//     "format": "waffr-backup", "version": 1, "created_at": "<UTC ISO>",
//     "kdf": {"name": "pbkdf2-hmac-sha256", "iterations": N, "salt": "<b64>"},
//     "cipher": "aes-256-gcm", "nonce": "<b64>", "data": "<b64>", "mac": "<b64>"
//   }
// The header fields are bound to the ciphertext as associated data, so
// changing any of them (e.g. lowering the iterations) breaks the MAC.
// Nothing readable outside `data`: no amounts, names or email.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// The file is not a Waffr backup, or one this version cannot read.
class BackupFormatException implements Exception {
  /// Why the file was refused (for logs, not users).
  final String reason;

  /// A refusal for [reason].
  const BackupFormatException(this.reason);

  @override
  String toString() => 'BackupFormatException: $reason';
}

/// The passphrase is wrong, or the file was changed after it was made.
/// AES-GCM cannot tell the two apart.
class BackupPassphraseException implements Exception {
  /// A wrong-passphrase-or-tampered refusal.
  const BackupPassphraseException();
}

/// Seals and opens backup files. Pure functions; the slow parts run in a
/// background isolate.
class LedgerBackupCodec {
  LedgerBackupCodec._();

  /// The `format` value of every backup file.
  static const String format = 'waffr-backup';

  /// The newest file version this app writes and reads.
  static const int version = 1;

  /// PBKDF2 iterations for new files (OWASP's figure for PBKDF2-SHA256).
  /// A backup file may end up in a cloud drive, where it can be attacked
  /// offline, and sealing happens rarely, so it gets the full count.
  static const int defaultIterations = 600000;

  /// Iterations a file may ask for. Below: too weak to trust. Above: a
  /// crafted file could freeze the app.
  static const int minIterations = 100000;

  /// See [minIterations].
  static const int maxIterations = 10000000;

  /// Shortest passphrase the app accepts for a new backup.
  static const int minPassphraseLength = 10;

  /// Largest file the app will try to open.
  static const int maxFileBytes = 50 * 1024 * 1024;

  static const String _kdfName = 'pbkdf2-hmac-sha256';
  static const String _cipherName = 'aes-256-gcm';

  /// Seals [body] (any JSON-encodable map) with [passphrase].
  static Future<Uint8List> seal({
    required Map<String, dynamic> body,
    required String passphrase,
    int iterations = defaultIterations,
    DateTime? now,
  }) {
    final random = Random.secure();
    return compute(_sealJob, (
      plain: Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(body)))),
      passphrase: passphrase,
      iterations: iterations,
      salt: Uint8List.fromList(
        List<int>.generate(16, (_) => random.nextInt(256)),
      ),
      createdAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
    ), debugLabel: 'seal backup');
  }

  /// Opens a backup [file] with [passphrase] and returns the sealed map.
  ///
  /// Throws [BackupFormatException] for anything that is not a readable
  /// backup, and [BackupPassphraseException] for a wrong passphrase or a
  /// changed file.
  static Future<Map<String, dynamic>> open({
    required Uint8List file,
    required String passphrase,
  }) async {
    final header = parseHeader(file);
    final plain = await compute(_openJob, (
      header: header,
      passphrase: passphrase,
    ), debugLabel: 'open backup');
    if (plain == null) throw const BackupPassphraseException();
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(gzip.decode(plain)));
    } catch (_) {
      throw const BackupFormatException('unreadable body');
    }
    if (decoded is! Map) {
      throw const BackupFormatException('body is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// The checked header of [file], before any slow work. Throws
  /// [BackupFormatException] when it is not a backup this app can read.
  static BackupHeader parseHeader(Uint8List file) {
    if (file.isEmpty || file.length > maxFileBytes) {
      throw const BackupFormatException('size');
    }
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(file));
    } catch (_) {
      throw const BackupFormatException('not json');
    }
    if (raw is! Map || raw['format'] != format) {
      throw const BackupFormatException('not a backup');
    }
    final fileVersion = raw['version'];
    if (fileVersion is! int || fileVersion < 1) {
      throw const BackupFormatException('bad version');
    }
    if (fileVersion > version) {
      throw const BackupFormatException('newer version');
    }
    final kdf = raw['kdf'];
    if (kdf is! Map ||
        kdf['name'] != _kdfName ||
        raw['cipher'] != _cipherName) {
      throw const BackupFormatException('unknown algorithm');
    }
    final iterations = kdf['iterations'];
    if (iterations is! int ||
        iterations < minIterations ||
        iterations > maxIterations) {
      throw const BackupFormatException('bad iterations');
    }
    final createdAt = raw['created_at'];
    if (createdAt is! String || DateTime.tryParse(createdAt) == null) {
      throw const BackupFormatException('bad date');
    }
    try {
      return BackupHeader(
        version: fileVersion,
        createdAt: createdAt,
        iterations: iterations,
        salt: base64Decode(kdf['salt'] as String),
        nonce: base64Decode(raw['nonce'] as String),
        data: base64Decode(raw['data'] as String),
        mac: base64Decode(raw['mac'] as String),
      );
    } catch (_) {
      throw const BackupFormatException('bad encoding');
    }
  }
}

/// The readable part of a backup file.
@immutable
class BackupHeader {
  /// File format version.
  final int version;

  /// When the backup was made (UTC ISO string, as stored).
  final String createdAt;

  /// PBKDF2 iterations for the passphrase.
  final int iterations;

  /// PBKDF2 salt.
  final List<int> salt;

  /// AES-GCM nonce.
  final List<int> nonce;

  /// AES-GCM ciphertext.
  final List<int> data;

  /// AES-GCM tag.
  final List<int> mac;

  /// A parsed header.
  const BackupHeader({
    required this.version,
    required this.createdAt,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.data,
    required this.mac,
  });

  /// When the backup was made, in local time.
  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();
}

final AesGcm _aes = AesGcm.with256bits();

// Associated data: every header field that is not part of the box itself,
// in a fixed order.
List<int> _associatedData(
  int fileVersion,
  String createdAt,
  int iterations,
  List<int> salt,
) {
  return utf8.encode(
    [
      LedgerBackupCodec.format,
      '$fileVersion',
      createdAt,
      LedgerBackupCodec._kdfName,
      '$iterations',
      base64Encode(salt),
      LedgerBackupCodec._cipherName,
    ].join('|'),
  );
}

Future<SecretKey> _deriveKey(
  String passphrase,
  List<int> salt,
  int iterations,
) {
  return Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
}

// Runs in a background isolate.
Future<Uint8List> _sealJob(
  ({
    Uint8List plain,
    String passphrase,
    int iterations,
    Uint8List salt,
    String createdAt,
  })
  input,
) async {
  final key = await _deriveKey(input.passphrase, input.salt, input.iterations);
  final box = await _aes.encrypt(
    input.plain,
    secretKey: key,
    nonce: _aes.newNonce(),
    aad: _associatedData(
      LedgerBackupCodec.version,
      input.createdAt,
      input.iterations,
      input.salt,
    ),
  );
  final file = {
    'format': LedgerBackupCodec.format,
    'version': LedgerBackupCodec.version,
    'created_at': input.createdAt,
    'kdf': {
      'name': LedgerBackupCodec._kdfName,
      'iterations': input.iterations,
      'salt': base64Encode(input.salt),
    },
    'cipher': LedgerBackupCodec._cipherName,
    'nonce': base64Encode(box.nonce),
    'data': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(file)));
}

// Runs in a background isolate. Null when the MAC check fails.
Future<Uint8List?> _openJob(
  ({BackupHeader header, String passphrase}) input,
) async {
  final header = input.header;
  final key = await _deriveKey(
    input.passphrase,
    header.salt,
    header.iterations,
  );
  try {
    final plain = await _aes.decrypt(
      SecretBox(header.data, nonce: header.nonce, mac: Mac(header.mac)),
      secretKey: key,
      aad: _associatedData(
        header.version,
        header.createdAt,
        header.iterations,
        header.salt,
      ),
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    return null;
  }
}
