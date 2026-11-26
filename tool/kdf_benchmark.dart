// Times one PBKDF2-HMAC-SHA256 derivation, the operation the app runs when it
// wraps or unwraps the data key (lib/core/security/data_key.dart), with the
// same pure-Dart implementation from package:cryptography.
//
//   dart run tool/kdf_benchmark.dart                  # JIT, quick look
//   dart compile exe tool/kdf_benchmark.dart -o /tmp/kdf && /tmp/kdf   # AOT
//
// Phones run the app AOT-compiled, so the AOT figure is the one to compare.
// On a phone (results print to the console; the screen stays blank):
//   flutter run --release -t tool/kdf_benchmark.dart

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

Future<Duration> _derive(int iterations) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final watch = Stopwatch()..start();
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode('benchmark password 1')),
    nonce: List<int>.generate(16, (i) => i),
  );
  await key.extractBytes();
  watch.stop();
  return watch.elapsed;
}

Future<void> main(List<String> args) async {
  final runs = args.isEmpty ? 3 : int.parse(args.first);
  await _derive(1000); // warm up
  for (final iterations in [210000, 600000]) {
    final times = <int>[];
    for (var i = 0; i < runs; i++) {
      times.add((await _derive(iterations)).inMilliseconds);
    }
    times.sort();
    // ignore: avoid_print
    print(
      'PBKDF2-HMAC-SHA256 $iterations iterations: '
      'median ${times[times.length ~/ 2]} ms, runs $times',
    );
  }
}
