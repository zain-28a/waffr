// Pbkdf2Engine: native is used only after its self-test, and any native
// problem falls back to Dart with the same result.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/pbkdf2.dart';

import '../../helpers/fake_native_pbkdf2.dart';

final _password = utf8.encode('كلمة المرور ٢٠٢٦');
final _salt = List<int>.generate(16, (i) => i);

Future<List<int>> _reference(int iterations) => dartOnlyEngine().deriveDart(
  password: _password,
  salt: _salt,
  iterations: iterations,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a correct native side is used after its self-test', () async {
    final fake = fakeNativeEngine();
    final result = await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 5000,
    );
    expect(result.backend, Pbkdf2Backend.native);
    expect(result.key, await _reference(5000));
    expect(fake.engine.disabledReason, isNull);
    // Self-test vectors first, then the real call.
    expect(fake.native.calls.length, selfTestVectors.length + 1);
  });

  test('the self-test runs once per engine', () async {
    final fake = fakeNativeEngine();
    await fake.engine.derive(password: _password, salt: _salt, iterations: 10);
    await fake.engine.derive(password: _password, salt: _salt, iterations: 10);
    expect(fake.native.calls.length, selfTestVectors.length + 2);
  });

  test('no native side: Dart, quietly', () async {
    final engine = dartOnlyEngine();
    final result = await engine.derive(
      password: _password,
      salt: _salt,
      iterations: 5000,
    );
    expect(result.backend, Pbkdf2Backend.dart);
    expect(result.key, await _reference(5000));
    expect(engine.disabledReason, 'no channel');
  });

  test('a channel without an answer (plugin missing): Dart', () async {
    // A channel nobody listens on.
    final engine = Pbkdf2Engine(channel: const MethodChannelStub().channel);
    final result = await engine.derive(
      password: _password,
      salt: _salt,
      iterations: 100,
    );
    expect(result.backend, Pbkdf2Backend.dart);
    expect(engine.disabledReason, 'not available');
  });

  for (final fault in [
    FakeNativeFault.wrongAlways,
    FakeNativeFault.error,
    FakeNativeFault.shortOutput,
  ]) {
    test(
      'a native side that fails its self-test (${fault.name}): Dart, same key',
      () async {
        final fake = fakeNativeEngine(fault: fault);
        final result = await fake.engine.derive(
          password: _password,
          salt: _salt,
          iterations: 5000,
        );
        expect(result.backend, Pbkdf2Backend.dart);
        expect(result.key, await _reference(5000));
        expect(fake.engine.disabledReason, isNotNull);
        // Native is not asked again after it failed.
        final asked = fake.native.calls.length;
        await fake.engine.derive(
          password: _password,
          salt: _salt,
          iterations: 10,
        );
        expect(fake.native.calls.length, asked);
      },
    );
  }

  test('a native call that hangs times out and Dart answers', () async {
    final fake = fakeNativeEngine(
      fault: FakeNativeFault.hang,
      timeout: const Duration(milliseconds: 50),
    );
    final result = await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 100,
    );
    expect(result.backend, Pbkdf2Backend.dart);
    expect(result.key, await _reference(100));
  });

  test('one failed call after a good self-test: that call is Dart, native stays on', () async {
    final first = selfTestVectors.length + 1;
    final fake = fakeNativeEngine(failCall: (call) => call == first);
    final failed = await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 100,
    );
    expect(failed.backend, Pbkdf2Backend.dart);
    expect(failed.key, await _reference(100));
    final next = await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 100,
    );
    expect(next.backend, Pbkdf2Backend.native);
    expect(next.key, failed.key);
  });

  test(
    'inputs outside the native bounds go to Dart without asking native',
    () async {
      final fake = fakeNativeEngine();
      final huge = List<int>.filled(Pbkdf2Engine.maxPasswordBytes + 1, 0x61);
      final result = await fake.engine.derive(
        password: huge,
        salt: _salt,
        iterations: 3,
      );
      expect(result.backend, Pbkdf2Backend.dart);
      expect(fake.native.calls, isEmpty);
    },
  );

  test('the iteration count is always the caller\'s', () async {
    final fake = fakeNativeEngine();
    await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 210000,
    );
    expect(fake.native.calls.last, 210000);
  });

  test('zero iterations are refused', () {
    expect(
      () => dartOnlyEngine().derive(
        password: _password,
        salt: _salt,
        iterations: 0,
      ),
      throwsArgumentError,
    );
  });
}

/// A channel with no handler registered.
class MethodChannelStub {
  const MethodChannelStub();

  /// The silent channel.
  MethodChannel get channel => const MethodChannel('test/pbkdf2/nobody');
}
