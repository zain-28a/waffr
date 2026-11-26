// A stand-in for the native PBKDF2 channel (android/.../Pbkdf2.kt,
// ios/Runner/AppDelegate.swift) so engine and caller tests can run in
// flutter_test. It derives with package:cryptography, so a "correct" fake
// gives the real answer; the knobs below make it fail in specific ways.

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/pbkdf2.dart';

/// How the fake native side misbehaves.
enum FakeNativeFault {
  /// Always correct.
  none,

  /// Wrong output for every call (fails the self-test).
  wrongAlways,

  /// Correct for the cheap self-test vectors, wrong above 4,096 iterations:
  /// a fault the self-test cannot see.
  wrongAboveSelfTest,

  /// Throws a PlatformException.
  error,

  /// Returns 16 bytes instead of 32.
  shortOutput,

  /// Never answers.
  hang,
}

var _channels = 0;

/// The fake's calls, for assertions.
class FakeNative {
  /// Every `derive` call's iteration count, in order.
  final List<int> calls = [];
}

/// An engine whose native side is the fake, on its own channel.
({Pbkdf2Engine engine, FakeNative native}) fakeNativeEngine({
  FakeNativeFault fault = FakeNativeFault.none,
  Duration timeout = const Duration(seconds: 30),
  bool Function(int call)? failCall,
}) {
  final channel = MethodChannel('test/pbkdf2/${_channels++}');
  final native = FakeNative();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'info') return {'platform': 'fake'};
        if (call.method != 'derive') return null;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final iterations = args['iterations'] as int;
        native.calls.add(iterations);
        if (failCall != null && failCall(native.calls.length)) {
          throw PlatformException(code: 'pbkdf2_failed');
        }
        switch (fault) {
          case FakeNativeFault.error:
            throw PlatformException(code: 'pbkdf2_failed');
          case FakeNativeFault.hang:
            return Completer<Uint8List>().future;
          case FakeNativeFault.shortOutput:
            return Uint8List(16);
          case FakeNativeFault.none:
          case FakeNativeFault.wrongAlways:
          case FakeNativeFault.wrongAboveSelfTest:
            break;
        }
        final key =
            await Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: iterations,
              bits: 256,
            ).deriveKey(
              secretKey: SecretKey(args['password'] as Uint8List),
              nonce: args['salt'] as Uint8List,
            );
        final bytes = Uint8List.fromList(await key.extractBytes());
        final corrupt =
            fault == FakeNativeFault.wrongAlways ||
            (fault == FakeNativeFault.wrongAboveSelfTest && iterations > 4096);
        if (corrupt) bytes[0] ^= 0xff;
        return bytes;
      });
  return (
    engine: Pbkdf2Engine(channel: channel, timeout: timeout),
    native: native,
  );
}

/// An engine with no native side at all (older builds, tests, desktop).
Pbkdf2Engine dartOnlyEngine() => Pbkdf2Engine(channel: null);
