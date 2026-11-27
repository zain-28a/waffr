// tool/kdf_benchmark.dart: the report has every field the device results
// are judged on, and the vector check catches a wrong native side.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/kdf_benchmark.dart';
import '../../tool/kdf_benchmark_vectors.dart';
import '../helpers/fake_native_pbkdf2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cheap = benchmarkVectors.where((v) => v.$4 <= 4096).toList();

  test(
    'a correct native side: every vector matches, every timing is there',
    () async {
      final fake = fakeNativeEngine();
      final lines = <String>[];
      final report = await runBenchmark(
        lines.add,
        engine: fake.engine,
        iterationCounts: const [1000, 2000],
        nativeRuns: 2,
        dartRuns: 1,
        vectors: cheap,
      );
      expect(report['report_version'], 1);
      expect(report['self_test_passed'], isTrue);
      expect(report['vectors_all_match'], isTrue);
      final timings = (report['timings'] as List).cast<Map>();
      expect(timings.map((t) => '${t['implementation']}@${t['iterations']}'), [
        'native@1000',
        'native_selected@1000',
        'dart@1000',
        'native@2000',
        'native_selected@2000',
        'dart@2000',
      ]);
      expect(report['native_method'], isA<String>());
      expect((timings.first['runs_ms'] as List).length, 2);
      expect(timings.first['worst_ms'], isA<int>());
      expect(report['native_worst_ms_within_target'], {
        '1000': isA<bool>(),
        '2000': isA<bool>(),
      });
      expect(lines, isNotEmpty);
    },
  );

  test('a wrong native side is reported, not hidden', () async {
    final fake = fakeNativeEngine(fault: FakeNativeFault.wrongAlways);
    final report = await runBenchmark(
      (_) {},
      engine: fake.engine,
      iterationCounts: const [1000],
      nativeRuns: 1,
      dartRuns: 1,
      vectors: cheap,
    );
    expect(report['self_test_passed'], isFalse);
    expect(report['vectors_all_match'], isFalse);
  });
}
