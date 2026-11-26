// The shared PBKDF2 vectors: the Dart implementation reproduces every one
// (outputs from Python's hashlib), and every copy of them, the Kotlin and
// Swift test data and the app's runtime self-test, is the same set.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/security/pbkdf2.dart';

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
];

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<Map<String, dynamic>> _vectors() {
  final json = jsonDecode(
    File('test/fixtures/pbkdf2_vectors.json').readAsStringSync(),
  ) as Map;
  return (json['vectors'] as List).cast<Map<String, dynamic>>();
}

void main() {
  final engine = Pbkdf2Engine(channel: null);

  test('the set covers the cases that can go wrong', () {
    final names = _vectors().map((v) => v['name']).toSet();
    expect(
      names,
      containsAll([
        'rfc7914',
        'arabic',
        'emoji',
        'long-100-bytes',
        'long-mixed',
        'exactly-64-bytes',
        'empty',
        'unnormalised-nfd',
        'app-210000',
        'app-600000',
        'app-arabic-210000',
      ]),
    );
    // The unnormalised case really holds two spellings of é.
    final nfd = _vectors().firstWhere((v) => v['name'] == 'unnormalised-nfd');
    expect(utf8.decode(_hex(nfd['password_hex'] as String)), 'é vs é');
  });

  for (final vector in _vectors()) {
    test(
      'Dart matches ${vector['name']} (${vector['iterations']} iterations)',
      () async {
        final derived = await engine.deriveDart(
          password: _hex(vector['password_hex'] as String),
          salt: _hex(vector['salt_hex'] as String),
          iterations: vector['iterations'] as int,
        );
        expect(_toHex(derived), vector['derived_hex']);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('the Android test data is the same file', () {
    expect(
      File('android/app/src/test/resources/pbkdf2_vectors.json')
          .readAsStringSync(),
      File('test/fixtures/pbkdf2_vectors.json').readAsStringSync(),
    );
  });

  test('the Swift test data holds the same vectors', () {
    final swift = File('ios/RunnerTests/RunnerTests.swift').readAsStringSync();
    for (final vector in _vectors()) {
      expect(
        swift,
        contains(
          '("${vector['name']}", "${vector['password_hex']}", '
          '"${vector['salt_hex']}", ${vector['iterations']}, "${vector['derived_hex']}")',
        ),
        reason: vector['name'] as String,
      );
    }
  });

  test('the runtime self-test is the cheap part of the same set', () {
    final cheap = _vectors()
        .where((v) => (v['iterations'] as int) <= 4096)
        .toList();
    expect(selfTestVectors.map((v) => v.name), cheap.map((v) => v['name']));
    for (var i = 0; i < cheap.length; i++) {
      expect(_toHex(selfTestVectors[i].derived), cheap[i]['derived_hex']);
      expect(_toHex(selfTestVectors[i].password), cheap[i]['password_hex']);
      expect(_toHex(selfTestVectors[i].salt), cheap[i]['salt_hex']);
      expect(selfTestVectors[i].iterations, cheap[i]['iterations']);
    }
  });
}
