// PBKDF2-HMAC-SHA256: the one place the app derives keys from passwords
// (the data-key wrap in data_key.dart and backup files in
// ledger_backup_codec.dart).
//
// Native first, pure Dart as the fallback:
//   * Android: javax.crypto HmacSHA256 (Conscrypt), android/.../Pbkdf2.kt
//   * iOS: CommonCrypto CCKeyDerivationPBKDF, ios/Runner/AppDelegate.swift
//   * everything else, and any native failure: package:cryptography, the
//     implementation the app has always used, in a background isolate.
//
// All three take the password as the same UTF-8 bytes, so they derive the
// same key (shared vectors in test/fixtures/pbkdf2_vectors.json). Native is
// used only after it reproduces known answers in this process; any mismatch
// or error means Dart. A native problem can make a derivation slower, never
// different.
//
// The iteration count is always the caller's: nothing here changes it.

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which implementation produced a key.
enum Pbkdf2Backend {
  /// The platform's own crypto (Android or iOS).
  native,

  /// package:cryptography in a background isolate.
  dart,
}

/// A derived key and how it was made.
@immutable
class Pbkdf2Result {
  /// The 32 derived bytes.
  final Uint8List key;

  /// The implementation that derived them.
  final Pbkdf2Backend backend;

  /// A result.
  const Pbkdf2Result(this.key, this.backend);
}

/// PBKDF2-HMAC-SHA256 with a 32-byte output.
class Pbkdf2Engine {
  /// The app-wide engine on the "waffr/pbkdf2" channel.
  static final Pbkdf2Engine instance = Pbkdf2Engine(
    channel: const MethodChannel('waffr/pbkdf2'),
  );

  /// An engine on [channel]; tests pass a mocked one.
  Pbkdf2Engine({
    required this.channel,
    this.timeout = const Duration(seconds: 30),
  });

  /// The native side, or null for Dart only.
  final MethodChannel? channel;

  /// How long one native derivation may take before Dart takes over.
  final Duration timeout;

  /// Output length in bytes.
  static const int length = 32;

  /// Bounds every implementation enforces.
  static const int maxIterations = 10000000;

  /// See [maxIterations].
  static const int maxPasswordBytes = 1024;

  Future<bool>? _nativeUsable;
  String? _disabledReason;
  Future<String>? _method;
  Map<String, Object?> _calibration = const {};

  /// The native method that does the work: [methodLoop] (our HMAC loop) or
  /// [methodFactory] (Android's own PBKDF2). Chosen once per process.
  static const String methodLoop = 'derive';

  /// See [methodLoop].
  static const String methodFactory = 'deriveWithFactory';

  /// Iterations of the short timing run that picks the faster method.
  static const int calibrationIterations = 10000;

  /// The factory must be at least this many times faster than the loop to be
  /// chosen, so noise never flips the choice on phones where they tie.
  static const double factorySpeedup = 1.25;

  /// What the calibration measured, for the benchmark report.
  Map<String, Object?> get calibration => _calibration;

  /// The native method used for non-empty passwords, chosen on first use.
  ///
  /// Android's own PBKDF2 (the `SecretKeyFactory`) is faster than our loop on
  /// some phones (a 32-bit Exynos 850: 1.5 s against 2.4 s at 210,000) and
  /// slower on others (every 64-bit phone tested). It takes characters, not
  /// bytes, so it is trusted only after it reproduces every known answer
  /// (Arabic, emoji, long and unnormalised passwords) on **this** device, and
  /// only if a short timing run shows it clearly faster. Anything else keeps
  /// the loop, which is the behaviour before this choice existed.
  Future<String> nativeMethod() => _method ??= _chooseMethod();

  Future<String> _chooseMethod() async {
    if (!await nativeUsable()) return methodLoop;
    try {
      // An empty password cannot go through the factory, so it is skipped.
      for (final vector in selfTestVectors.where(
        (v) => v.password.isNotEmpty,
      )) {
        final got = await deriveNative(
          password: vector.password,
          salt: vector.salt,
          iterations: vector.iterations,
          method: methodFactory,
        );
        if (!listEquals(got, vector.derived)) {
          _calibration = {'factory': 'mismatch:${vector.name}'};
          return methodLoop;
        }
      }
      final password = List<int>.generate(12, (i) => 97 + i);
      final salt = List<int>.generate(16, (i) => i);
      Future<int> time(String method, int iterations) async {
        final watch = Stopwatch()..start();
        await deriveNative(
          password: password,
          salt: salt,
          iterations: iterations,
          method: method,
        );
        return watch.elapsedMicroseconds;
      }

      await time(methodLoop, 1000); // warm-up, not counted
      await time(methodFactory, 1000);
      final loop = await time(methodLoop, calibrationIterations);
      final factory = await time(methodFactory, calibrationIterations);
      final chosen = loop > factorySpeedup * factory
          ? methodFactory
          : methodLoop;
      _calibration = {
        'loop_us': loop,
        'factory_us': factory,
        'iterations': calibrationIterations,
        'chosen': chosen,
      };
      return chosen;
    } catch (error) {
      _calibration = {'factory': 'unavailable:${error.runtimeType}'};
      return methodLoop;
    }
  }

  /// Why native is off in this process, or null (for logs and the benchmark).
  String? get disabledReason => _disabledReason;

  /// Derives the key for [password] (its UTF-8 bytes), [salt] and
  /// [iterations], natively when that passed its self-test.
  Future<Pbkdf2Result> derive({
    required List<int> password,
    required List<int> salt,
    required int iterations,
  }) async {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    // Inputs outside the native bounds go to Dart, which takes anything the
    // app ever accepted.
    if (_withinNativeBounds(password, salt, iterations) &&
        await nativeUsable()) {
      try {
        final key = await deriveNative(
          password: password,
          salt: salt,
          iterations: iterations,
          method: password.isEmpty ? methodLoop : await nativeMethod(),
        );
        return Pbkdf2Result(key, Pbkdf2Backend.native);
      } catch (error) {
        // One failed call: this derivation goes to Dart; native stays on.
        debugPrint(
          'PBKDF2: native call failed (${error.runtimeType}); using Dart',
        );
      }
    }
    return Pbkdf2Result(
      await deriveDart(password: password, salt: salt, iterations: iterations),
      Pbkdf2Backend.dart,
    );
  }

  /// Derives a key that will protect **new** data (a new wrap of the data
  /// key, a new backup file).
  ///
  /// The key is always the Dart one, from the same code earlier app versions
  /// used, so a fault in the native code can never end up in anything
  /// written. Native runs alongside as a check: if it disagrees, it is
  /// switched off for this process. Reading (unwrap, opening a backup) uses
  /// [derive], where a wrong native key just fails the MAC and is retried in
  /// Dart.
  Future<Uint8List> deriveForWriting({
    required List<int> password,
    required List<int> salt,
    required int iterations,
  }) async {
    final dart = deriveDart(
      password: password,
      salt: salt,
      iterations: iterations,
    );
    Future<Uint8List?>? native;
    if (_withinNativeBounds(password, salt, iterations) &&
        await nativeUsable()) {
      native = deriveNative(
        password: password,
        salt: salt,
        iterations: iterations,
        method: password.isEmpty ? methodLoop : await nativeMethod(),
      ).then<Uint8List?>((key) => key, onError: (_) => null);
    }
    final key = await dart;
    if (native != null) {
      final check = await native;
      if (check != null && !listEquals(check, key)) {
        _nativeUsable = Future.value(_disable('mismatch:write'));
      }
    }
    return key;
  }

  /// True once native has reproduced every known answer in this process.
  /// Runs the self-test on the first call; later calls reuse its result.
  Future<bool> nativeUsable() => _nativeUsable ??= _selfTest();

  /// Pure-Dart derivation in a background isolate (no fallback, no self-test).
  Future<Uint8List> deriveDart({
    required List<int> password,
    required List<int> salt,
    required int iterations,
  }) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    return compute(_dartJob, (
      password: Uint8List.fromList(password),
      salt: Uint8List.fromList(salt),
      iterations: iterations,
    ), debugLabel: 'pbkdf2');
  }

  /// One native derivation (no fallback, no self-test). Throws when native
  /// is missing, fails, times out or returns anything but 32 bytes.
  Future<Uint8List> deriveNative({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    String method = 'derive',
  }) async {
    final native = channel;
    if (native == null) throw MissingPluginException('no channel');
    _check(password, salt, iterations);
    final out = await native
        .invokeMethod<Uint8List>(method, {
          'password': Uint8List.fromList(password),
          'salt': Uint8List.fromList(salt),
          'iterations': iterations,
          'length': length,
        })
        .timeout(timeout);
    if (out == null || out.length != length) {
      throw const FormatException('native PBKDF2 returned a bad length');
    }
    return out;
  }

  /// The platform's description of itself and its crypto provider, or null.
  Future<Map<String, Object?>?> platformInfo() async {
    try {
      final info = await channel?.invokeMapMethod<String, Object?>('info');
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _selfTest() async {
    if (channel == null) return _disable('no channel');
    try {
      for (final vector in selfTestVectors) {
        final got = await deriveNative(
          password: vector.password,
          salt: vector.salt,
          iterations: vector.iterations,
        );
        if (!listEquals(got, vector.derived)) {
          return _disable('mismatch:${vector.name}');
        }
      }
      return true;
    } on MissingPluginException {
      return _disable('not available');
    } catch (error) {
      return _disable('error:${error.runtimeType}');
    }
  }

  bool _disable(String reason) {
    _disabledReason = reason;
    if (reason != 'not available' && reason != 'no channel') {
      debugPrint('PBKDF2: native disabled ($reason); using Dart');
    }
    return false;
  }

  static bool _withinNativeBounds(
    List<int> password,
    List<int> salt,
    int iterations,
  ) =>
      iterations >= 1 &&
      iterations <= maxIterations &&
      salt.isNotEmpty &&
      salt.length <= 64 &&
      password.length <= maxPasswordBytes;

  static void _check(List<int> password, List<int> salt, int iterations) {
    if (iterations < 1 || iterations > maxIterations) {
      throw ArgumentError.value(iterations, 'iterations');
    }
    if (salt.isEmpty || salt.length > 64) {
      throw ArgumentError.value(salt.length, 'salt length');
    }
    if (password.length > maxPasswordBytes) {
      throw ArgumentError.value(password.length, 'password length');
    }
  }
}

/// A known answer for the self-test.
@immutable
class Pbkdf2Vector {
  /// Name in logs.
  final String name;

  /// Password bytes.
  final List<int> password;

  /// Salt bytes.
  final List<int> salt;

  /// Iterations.
  final int iterations;

  /// Expected output.
  final List<int> derived;

  /// A vector.
  const Pbkdf2Vector(
    this.name,
    this.password,
    this.salt,
    this.iterations,
    this.derived,
  );
}

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
];

/// The self-test: the cheap cases of test/fixtures/pbkdf2_vectors.json
/// (outputs from Python's hashlib), covering ASCII, Arabic, emoji, a
/// password longer than the HMAC block, an empty password and unnormalised
/// text. A few milliseconds natively.
// BEGIN GENERATED SELF-TEST VECTORS (tool/gen_pbkdf2_vectors.py)
// dart format off
final List<Pbkdf2Vector> selfTestVectors = [
  Pbkdf2Vector(
    'rfc7914',
    _hex('706173737764'),
    _hex('73616c74'),
    1,
    _hex('55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'),
  ),
  Pbkdf2Vector(
    'ascii-1',
    _hex('70617373776f7264'),
    _hex('73616c74'),
    1,
    _hex('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'),
  ),
  Pbkdf2Vector(
    'ascii-2',
    _hex('70617373776f7264'),
    _hex('73616c74'),
    2,
    _hex('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'),
  ),
  Pbkdf2Vector(
    'ascii-4096',
    _hex('70617373776f7264'),
    _hex('73616c74'),
    4096,
    _hex('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a'),
  ),
  Pbkdf2Vector(
    'arabic',
    _hex('d983d984d985d8a920d8b3d8b120d8b9d8b1d8a8d98ad8a920d9a1d9a2d9a3'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    1000,
    _hex('6c6f32e04cbf6506f427dc5be6d5ba8b609e5e0862a50757cf88b170290e2416'),
  ),
  Pbkdf2Vector(
    'arabic-salt32',
    _hex('d985d8b1d8add8a8d8a720d8a8d8a7d984d8b9d8a7d984d985'),
    _hex('6465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80818283'),
    1000,
    _hex('f6de7a2cf092d2e176b58a11f0db63568fcd42a86c9d03f7afc5eae74a54c900'),
  ),
  Pbkdf2Vector(
    'emoji',
    _hex('656d6f6a6920f09f9490f09f918df09f8fbd2070617373'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    1000,
    _hex('40ffbcbed3e9df56c6092c82119906def31cf90d8fb5eefb786296c3dfc0f1a5'),
  ),
  Pbkdf2Vector(
    'long-100-bytes',
    _hex('78787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    1000,
    _hex('7361429554ed1659d8d9e8f94f65ff15798a3c4739b530e00d68a5c95540dab2'),
  ),
  Pbkdf2Vector(
    'long-mixed',
    _hex('d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920d8b7d988d98ad984d8a920f09f9490f09f9490f09f9490f09f9490f09f9490f09f9490f09f9490f09f9490f09f9490f09f9490'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    3,
    _hex('8418fed9a9c756fa2c9b4a57f7e05ef2bd2436684cdfaaaf1d30d3c858b4555c'),
  ),
  Pbkdf2Vector(
    'exactly-64-bytes',
    _hex('6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    5,
    _hex('e80c4cbcd756cdbae649f072d930c85d56740e522cdb135a3c0d33d8a1645f7a'),
  ),
  Pbkdf2Vector(
    'empty',
    _hex(''),
    _hex('000102030405060708090a0b0c0d0e0f'),
    10,
    _hex('595bd935ae36fc1e8960427231aa29d9198368740b19b26517bd9d4cb586fda2'),
  ),
  Pbkdf2Vector(
    'unnormalised-nfd',
    _hex('65cc8120767320c3a9'),
    _hex('000102030405060708090a0b0c0d0e0f'),
    7,
    _hex('93f6b2a484091b5660c314f0dba1164c430ebcc405d042f58c6ef99663bffe10'),
  ),
];
// dart format on
// END GENERATED SELF-TEST VECTORS

// Runs in a background isolate: the implementation the app always used.
Future<Uint8List> _dartJob(
  ({Uint8List password, Uint8List salt, int iterations}) input,
) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: input.iterations,
    bits: Pbkdf2Engine.length * 8,
  ).deriveKey(secretKey: SecretKey(input.password), nonce: input.salt);
  return Uint8List.fromList(await key.extractBytes());
}
