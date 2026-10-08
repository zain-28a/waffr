// On-device encryption for private sync fields. The data key never leaves the
// phone in readable form: the server only keeps a copy wrapped with a key
// derived from the user's password, so notes and names stay unreadable in
// the database.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final AesGcm _aes = AesGcm.with256bits();

// Encrypts and decrypts single text values with the account's data key.
class DataCipher {
  DataCipher(List<int> keyBytes) : _key = SecretKey(keyBytes);

  final SecretKey _key;

  static const String prefix = 'enc1:';

  static bool isSealed(String? value) =>
      value != null && value.startsWith(prefix);

  // Empty values stay empty so optional fields keep their meaning.
  Future<String?> seal(String? value) async {
    if (value == null || value.isEmpty || isSealed(value)) return value;
    final box = await _aes.encrypt(
      utf8.encode(value),
      secretKey: _key,
      nonce: _aes.newNonce(),
    );
    return '$prefix${base64Encode(box.concatenation())}';
  }

  // Values written before encryption pass through unchanged. A value that
  // fails to decrypt comes back null rather than as ciphertext.
  Future<String?> open(String? value) async {
    if (!isSealed(value)) return value;
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(value!.substring(prefix.length)),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: _key));
    } catch (_) {
      return null;
    }
  }
}

// The data key as the server stores it: encrypted with the password key.
class WrappedDataKey {
  const WrappedDataKey({
    required this.salt,
    required this.iterations,
    required this.wrappedKey,
  });

  final String salt;
  final int iterations;
  final String wrappedKey;

  static WrappedDataKey? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final salt = raw['salt']?.toString() ?? '';
    final wrapped = raw['wrapped_key']?.toString() ?? '';
    final iterations = int.tryParse(raw['iterations']?.toString() ?? '');
    if (salt.isEmpty || wrapped.isEmpty || iterations == null) return null;
    return WrappedDataKey(
      salt: salt,
      iterations: iterations,
      wrappedKey: wrapped,
    );
  }

  Map<String, dynamic> toJson() => {
        'salt': salt,
        'iterations': iterations,
        'wrapped_key': wrappedKey,
      };
}

// A fresh data key and the wrapped copy to upload for it.
class NewDataKey {
  const NewDataKey(this.key, this.wrapped);

  final Uint8List key;
  final WrappedDataKey wrapped;
}

// Holds the unwrapped key in secure storage for the signed-in account.
class DataKeyStore {
  DataKeyStore._();

  static final DataKeyStore instance = DataKeyStore._();

  static const String _storageKey = 'waffer_data_key';
  static const int defaultIterations = 210000;
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  DataCipher? _cached;

  Future<DataCipher?> cipher() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = (await _secure.read(key: _storageKey))?.trim() ?? '';
    if (stored.isEmpty) return null;
    try {
      return _cached = DataCipher(base64Decode(stored));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<int> key) async {
    await _secure.write(key: _storageKey, value: base64Encode(key));
    _cached = DataCipher(key);
  }

  Future<void> clear() async {
    _cached = null;
    await _secure.delete(key: _storageKey);
  }

  // New random key, wrapped with the password for upload.
  static Future<NewDataKey> create(
    String password, {
    int iterations = defaultIterations,
  }) async {
    final key = _randomBytes(32);
    return NewDataKey(key, await wrap(key, password, iterations: iterations));
  }

  // Wrap an existing key with a password, e.g. after a password change.
  static Future<WrappedDataKey> wrap(
    List<int> key,
    String password, {
    int iterations = defaultIterations,
  }) async {
    final salt = _randomBytes(16);
    final passwordKey = await _passwordKey(password, salt, iterations);
    final box = await _aes.encrypt(
      key,
      secretKey: SecretKey(passwordKey),
      nonce: _aes.newNonce(),
    );
    return WrappedDataKey(
      salt: base64Encode(salt),
      iterations: iterations,
      wrappedKey: base64Encode(box.concatenation()),
    );
  }

  // Null when the password does not open the wrapped key.
  static Future<Uint8List?> unwrap(
    String password,
    WrappedDataKey wrapped,
  ) async {
    try {
      final passwordKey = await _passwordKey(
        password,
        base64Decode(wrapped.salt),
        wrapped.iterations,
      );
      final box = SecretBox.fromConcatenation(
        base64Decode(wrapped.wrappedKey),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final key = await _aes.decrypt(box, secretKey: SecretKey(passwordKey));
      return Uint8List.fromList(key);
    } catch (_) {
      return null;
    }
  }

  // PBKDF2 is slow on purpose; run it off the UI isolate.
  static Future<List<int>> _passwordKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    return compute(_derivePasswordKey, (password, salt, iterations));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

Future<List<int>> _derivePasswordKey(
  (String, List<int>, int) input,
) async {
  final (password, salt, iterations) = input;
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final derived = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  return derived.extractBytes();
}
