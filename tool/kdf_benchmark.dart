// On-device PBKDF2 check and benchmark (NATIVE_PBKDF2_PLAN.md §4,
// KDF_BENCHMARK.md for how to install and run it).
//
// A separate app (package com.waffr.app.kdfbench on Android), so it never
// touches the real app or its data. It:
//   1. reports the device, OS and crypto provider;
//   2. runs the engine's self-test;
//   3. checks the native implementation against every shared vector
//      (outputs from Python's hashlib), including 210,000 and 600,000;
//   4. times one derivation at 210,000 and 600,000 iterations: native (and on
//      Android the platform SecretKeyFactory, for comparison) 5 runs each,
//      pure Dart 3 runs each, after one warm-up run;
//   5. shows the results as JSON to copy or share.
//
// Build: flutter build apk --release -t tool/kdf_benchmark.dart \
//          -P waffrBenchmark=true --dart-define=WAFFR_COMMIT=<git sha>
// Desktop or CI quick look (Dart only): dart run tool/kdf_benchmark.dart is
// not supported; use flutter test test/core/security instead.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:waffr/core/security/pbkdf2.dart';

import 'kdf_benchmark_vectors.dart';

/// The commit the build came from (set by CI with --dart-define).
const String _commit = String.fromEnvironment(
  'WAFFR_COMMIT',
  defaultValue: 'local',
);

/// Version of the JSON this app prints; bump when the fields change.
const int _reportVersion = 1;

/// The target from NATIVE_PBKDF2_PLAN.md: worst of 5 native runs.
const int _targetMs = 2000;

const List<int> _iterationCounts = [210000, 600000];
const int _nativeRuns = 5;
const int _dartRuns = 3;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatelessWidget {
  const _BenchmarkApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waffr KDF benchmark',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const _BenchmarkPage(),
    );
  }
}

class _BenchmarkPage extends StatefulWidget {
  const _BenchmarkPage();

  @override
  State<_BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<_BenchmarkPage> {
  final List<String> _log = [];
  Map<String, Object?>? _report;
  bool _running = false;

  void _say(String line) {
    debugPrint('KDF: $line');
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = null;
      _log.clear();
    });
    try {
      final report = await runBenchmark(_say);
      // One line in the device log too, for adb users.
      debugPrint('KDF_REPORT ${jsonEncode(report)}');
      if (mounted) setState(() => _report = report);
      _say('Done. Copy or share the results below.');
    } catch (error) {
      _say('FAILED: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final text = report == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(report);
    return Scaffold(
      appBar: AppBar(title: const Text('Waffr KDF benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Keep the phone on, unlocked and plugged in or above 50% battery, '
            'with battery saver off. Do not switch apps while it runs '
            '(about 1–3 minutes).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Running…' : 'Run benchmark'),
          ),
          const SizedBox(height: 12),
          for (final line in _log)
            Text(
              line,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          if (text != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  child: const Text('Copy results'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(text: text)),
                  child: const Text('Share results'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
];

/// Runs every step and returns the report. [say] receives progress lines.
///
/// Tests pass a fake [engine] and small [iterationCounts].
Future<Map<String, Object?>> runBenchmark(
  void Function(String) say, {
  Pbkdf2Engine? engine,
  List<int> iterationCounts = _iterationCounts,
  int nativeRuns = _nativeRuns,
  int dartRuns = _dartRuns,
  List<(String, String, String, int, String)> vectors = benchmarkVectors,
}) async {
  final Pbkdf2Engine kdf = engine ?? Pbkdf2Engine.instance;
  final info = await kdf.platformInfo();
  say(
    'Device: ${info?['manufacturer'] ?? ''} ${info?['model'] ?? 'unknown'} '
    '(${info?['platform'] ?? Platform.operatingSystem} ${info?['os_version'] ?? ''})',
  );

  final selfTest = await kdf.nativeUsable();
  final nativeMethod = await kdf.nativeMethod();
  say('Native method chosen: $nativeMethod ${kdf.calibration}');
  say('Self-test: ${selfTest ? 'passed' : 'FAILED (${kdf.disabledReason})'}');

  // Every shared vector through native, including the expensive ones.
  final vectorResults = <Map<String, Object?>>[];
  var allMatch = true;
  for (final (name, password, salt, iterations, derived) in vectors) {
    String outcome;
    try {
      final got = await kdf.deriveNative(
        password: _hex(password),
        salt: _hex(salt),
        iterations: iterations,
      );
      outcome = listEquals(got, _hex(derived)) ? 'match' : 'MISMATCH';
    } catch (error) {
      outcome = 'error:${error.runtimeType}';
    }
    if (outcome != 'match') allMatch = false;
    vectorResults.add({
      'name': name,
      'iterations': iterations,
      'result': outcome,
    });
  }
  say(
    'Vectors: ${allMatch ? 'all ${vectors.length} match' : 'SOME DO NOT MATCH'}',
  );

  final password = utf8.encode('correct horse 1');
  final salt = List<int>.generate(16, (i) => i);
  final timings = <Map<String, Object?>>[];

  Future<void> time(
    String implementation,
    int iterations,
    int runs,
    Future<Object?> Function() derive,
  ) async {
    final runsMs = <int>[];
    String? error;
    try {
      await derive(); // warm-up, not counted
      for (var i = 0; i < runs; i++) {
        final watch = Stopwatch()..start();
        await derive();
        runsMs.add(watch.elapsedMilliseconds);
      }
    } catch (e) {
      error = e.runtimeType.toString();
    }
    final sorted = [...runsMs]..sort();
    final entry = <String, Object?>{
      'implementation': implementation,
      'iterations': iterations,
      'runs_ms': runsMs,
      if (sorted.isNotEmpty) 'median_ms': sorted[sorted.length ~/ 2],
      if (sorted.isNotEmpty) 'worst_ms': sorted.last,
      'error': ?error,
    };
    timings.add(entry);
    say(
      '$implementation @ $iterations: '
      '${error ?? 'median ${entry['median_ms']} ms, worst ${entry['worst_ms']} ms'}',
    );
  }

  for (final iterations in iterationCounts) {
    await time(
      'native',
      iterations,
      nativeRuns,
      () => kdf.deriveNative(
        password: password,
        salt: salt,
        iterations: iterations,
      ),
    );
    await time(
      'native_selected',
      iterations,
      nativeRuns,
      () => kdf.deriveNative(
        password: password,
        salt: salt,
        iterations: iterations,
        method: nativeMethod,
      ),
    );
    if (info?['platform'] == 'android') {
      await time(
        'android_secret_key_factory',
        iterations,
        nativeRuns,
        () => kdf.deriveNative(
          password: password,
          salt: salt,
          iterations: iterations,
          method: 'deriveWithFactory',
        ),
      );
    }
    await time(
      'dart',
      iterations,
      dartRuns,
      () => kdf.deriveDart(
        password: password,
        salt: salt,
        iterations: iterations,
      ),
    );
  }

  int? worst(String implementation, int iterations) => timings
      .where(
        (t) =>
            t['implementation'] == implementation &&
            t['iterations'] == iterations,
      )
      .map((t) => t['worst_ms'] as int?)
      .firstOrNull;

  return {
    'report_version': _reportVersion,
    'commit': _commit,
    'measured_at': DateTime.now().toUtc().toIso8601String(),
    'build_mode': kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug'),
    'device': info,
    'self_test_passed': selfTest,
    'native_method': nativeMethod,
    'native_method_calibration': kdf.calibration,
    'self_test_disabled_reason': kdf.disabledReason,
    'vectors_all_match': allMatch,
    'vectors': vectorResults,
    'timings': timings,
    'target_ms': _targetMs,
    'native_worst_ms_within_target': {
      for (final iterations in iterationCounts)
        '$iterations': switch (worst('native', iterations)) {
          final int ms => ms <= _targetMs,
          _ => null,
        },
    },
  };
}
