// Pbkdf2Engine.nativeMethod: Android's own PBKDF2 (the SecretKeyFactory) is
// used only when it reproduces every known answer on the device AND is clearly
// faster than our HMAC loop; otherwise the loop, as before.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/pbkdf2.dart';

import '../../helpers/fake_native_pbkdf2.dart';

final _password = utf8.encode('كلمة المرور ٢٠٢٦ 🔐');
final _salt = List<int>.generate(16, (i) => i);
const _slow = Duration(milliseconds: 80);
const _fast = Duration(milliseconds: 2);

Future<List<int>> _reference(List<int> password, int iterations) =>
    dartOnlyEngine().deriveDart(
      password: password,
      salt: _salt,
      iterations: iterations,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a clearly faster factory is chosen, and the key is the same', () async {
    final fake = fakeNativeEngine(
      factory: FakeFactory.correct,
      loopDelay: _slow,
      factoryDelay: _fast,
    );
    expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodFactory);
    final before = fake.native.calls.length;
    final result = await fake.engine.derive(
      password: _password,
      salt: _salt,
      iterations: 3000,
    );
    expect(result.backend, Pbkdf2Backend.native);
    expect(result.key, await _reference(_password, 3000));
    // The derivation went through the factory, not the loop.
    expect(fake.native.calls.length, before);
    expect(fake.native.factoryCalls.last, 3000);
    expect(fake.engine.calibration['chosen'], Pbkdf2Engine.methodFactory);
  });

  test('a slower factory is not chosen', () async {
    final fake = fakeNativeEngine(
      factory: FakeFactory.correct,
      loopDelay: _fast,
      factoryDelay: _slow,
    );
    expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodLoop);
  });

  test('a factory that merely ties is not chosen (no flapping)', () async {
    final fake = fakeNativeEngine(factory: FakeFactory.correct);
    expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodLoop);
  });

  test(
    'a factory with a wrong answer is never chosen, native stays on',
    () async {
      final fake = fakeNativeEngine(
        factory: FakeFactory.wrong,
        loopDelay: _slow,
        factoryDelay: _fast,
      );
      expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodLoop);
      expect(fake.engine.calibration['factory'], startsWith('mismatch'));
      expect(await fake.engine.nativeUsable(), isTrue);
      final result = await fake.engine.derive(
        password: _password,
        salt: _salt,
        iterations: 2000,
      );
      expect(result.backend, Pbkdf2Backend.native);
      expect(result.key, await _reference(_password, 2000));
    },
  );

  test('a factory that errors or is missing keeps the loop', () async {
    for (final factory in [FakeFactory.error, FakeFactory.absent]) {
      final fake = fakeNativeEngine(factory: factory, loopDelay: _slow);
      expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodLoop);
    }
  });

  test('an empty password never goes through the factory', () async {
    final fake = fakeNativeEngine(
      factory: FakeFactory.correct,
      loopDelay: _slow,
      factoryDelay: _fast,
    );
    expect(await fake.engine.nativeMethod(), Pbkdf2Engine.methodFactory);
    final used = fake.native.factoryCalls.length;
    final result = await fake.engine.derive(
      password: const <int>[],
      salt: _salt,
      iterations: 500,
    );
    expect(result.key, await _reference(const <int>[], 500));
    expect(fake.native.factoryCalls.length, used);
  });

  test('the choice is made once per engine', () async {
    final fake = fakeNativeEngine(
      factory: FakeFactory.correct,
      loopDelay: _slow,
      factoryDelay: _fast,
    );
    await fake.engine.nativeMethod();
    final calls = fake.native.factoryCalls.length;
    await fake.engine.nativeMethod();
    await fake.engine.derive(password: _password, salt: _salt, iterations: 10);
    // Only the derivation itself added a call.
    expect(fake.native.factoryCalls.length, calls + 1);
  });

  test('without native, the loop is the answer and nothing is asked', () async {
    final engine = dartOnlyEngine();
    expect(await engine.nativeMethod(), Pbkdf2Engine.methodLoop);
  });

  test(
    'new data is still written with the Dart key when the factory is chosen',
    () async {
      final fake = fakeNativeEngine(
        factory: FakeFactory.correct,
        loopDelay: _slow,
        factoryDelay: _fast,
      );
      final key = await fake.engine.deriveForWriting(
        password: _password,
        salt: _salt,
        iterations: 2500,
      );
      expect(key, await _reference(_password, 2500));
      expect(fake.engine.disabledReason, isNull);
    },
  );
}
