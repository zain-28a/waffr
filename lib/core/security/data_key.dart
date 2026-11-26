// On-device encryption for private sync fields. The data key never leaves the
// phone in readable form: the server only keeps a copy wrapped with a key
// derived from the user's password, so notes and names stay unreadable in
// the database.
//
// AES-GCM is pure Dart; SyncService seals whole requests in a background
// isolate. The slow step of wrapping and unwrapping, PBKDF2, goes through
// Pbkdf2Engine (pbkdf2.dart): native on Android and iOS, Dart in a
// background isolate otherwise. Either way the UI thread never waits on it.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waffr/core/security/pbkdf2.dart';

final AesGcm _aes = AesGcm.with256bits();

/// Encrypts and decrypts single text values with the account's data key.
class DataCipher {
  /// A cipher for the 32-byte [keyBytes].
  DataCipher(List<int> keyBytes)
    : keyBytes = Uint8List.fromList(keyBytes),
      _key = SecretKey(keyBytes);

  /// The raw key, so a background isolate can build its own cipher.
  final Uint8List keyBytes;

  final SecretKey _key;

  /// Marks a sealed value: `enc1:` followed by base64 nonce, text and MAC.
  static const String prefix = 'enc1:';

  /// True when [value] was produced by [seal].
  static bool isSealed(String? value) =>
      value != null && value.startsWith(prefix);

  /// Encrypts [value]. Empty values stay empty so optional fields keep
  /// their meaning, and sealed values are not sealed twice.
  Future<String?> seal(String? value) async {
    if (value == null || value.isEmpty || isSealed(value)) return value;
    final box = await _aes.encrypt(
      utf8.encode(value),
      secretKey: _key,
      nonce: _aes.newNonce(),
    );
    return '$prefix${base64Encode(box.concatenation())}';
  }

  /// Decrypts [value]. Values written before encryption pass through
  /// unchanged; a value that fails to decrypt comes back null rather than
  /// as ciphertext.
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

/// The data key as the server stores it: encrypted with the password key.
class WrappedDataKey {
  /// A wrapped key with its PBKDF2 [salt] and [iterations].
  const WrappedDataKey({
    required this.salt,
    required this.iterations,
    required this.wrappedKey,
  });

  /// Base64 PBKDF2 salt.
  final String salt;

  /// PBKDF2 iteration count used for this copy.
  final int iterations;

  /// Base64 AES-GCM box (nonce, encrypted key, MAC).
  final String wrappedKey;

  /// Reads the `data_key` object from `/auth/me`; null when incomplete.
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

  /// The JSON shape the server stores.
  Map<String, dynamic> toJson() => {
    'salt': salt,
    'iterations': iterations,
    'wrapped_key': wrappedKey,
  };
}

/// A fresh data key and the wrapped copy to upload for it.
class NewDataKey {
  /// Pairs the raw [key] with its [wrapped] upload copy.
  const NewDataKey(this.key, this.wrapped);

  /// The raw 32-byte data key.
  final Uint8List key;

  /// [key] wrapped with the password.
  final WrappedDataKey wrapped;
}

/// Holds the unwrapped key in secure storage for the signed-in account.
class DataKeyStore {
  DataKeyStore._();

  /// The app-wide store.
  static final DataKeyStore instance = DataKeyStore._();

  static const String _storageKey = 'waffer_data_key';

  /// PBKDF2 iterations for new wrapped copies.
  static const int defaultIterations = 210000;

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  DataCipher? _cached;

  /// The cipher for the stored key, or null when this device has none
  /// (guest, or a session from before encryption).
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

  /// Stores [key] for this account and caches its cipher.
  Future<void> save(List<int> key) async {
    await _secure.write(key: _storageKey, value: base64Encode(key));
    _cached = DataCipher(key);
  }

  /// Forgets the key (sign-out or account switch).
  Future<void> clear() async {
    _cached = null;
    await _secure.delete(key: _storageKey);
  }

  /// A new random key, wrapped with [password] for upload.
  static Future<NewDataKey> create(
    String password, {
    int iterations = defaultIterations,
  }) async {
    final key = _randomBytes(32);
    return NewDataKey(key, await wrap(key, password, iterations: iterations));
  }

  /// Derives the password keys. Tests swap in an engine with a mocked
  /// native side.
  @visibleForTesting
  static Pbkdf2Engine engine = Pbkdf2Engine.instance;

  /// Wraps an existing [key] with [password], e.g. after a password change.
  static Future<WrappedDataKey> wrap(
    List<int> key,
    String password, {
    int iterations = defaultIterations,
  }) async {
    final salt = _randomBytes(16);
    // A new wrap: derived by the Dart code, checked against native (see
    // Pbkdf2Engine.deriveForWriting).
    final passwordKey = await engine.deriveForWriting(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
    );
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

  /// The raw key inside [wrapped], or null when [password] does not open it.
  ///
  /// If a natively derived key does not open the box, the Dart one is tried
  /// before giving up, so a fault in the native code could only ever make
  /// a sign-in slower, never lock anyone out of an existing key.
  static Future<Uint8List?> unwrap(
    String password,
    WrappedDataKey wrapped,
  ) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(wrapped.wrappedKey),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final passwordBytes = utf8.encode(password);
      final salt = base64Decode(wrapped.salt);
      final derived = await engine.derive(
        password: passwordBytes,
        salt: salt,
        iterations: wrapped.iterations,
      );
      final opened = await _open(box, derived.key);
      if (opened != null || derived.backend == Pbkdf2Backend.dart) {
        return opened;
      }
      final checked = await engine.deriveDart(
        password: passwordBytes,
        salt: salt,
        iterations: wrapped.iterations,
      );
      if (!listEquals(checked, derived.key)) {
        debugPrint('PBKDF2: native and Dart keys differ; opened with Dart');
      }
      return await _open(box, checked);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _open(SecretBox box, List<int> passwordKey) async {
    try {
      final key = await _aes.decrypt(box, secretKey: SecretKey(passwordKey));
      return Uint8List.fromList(key);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
