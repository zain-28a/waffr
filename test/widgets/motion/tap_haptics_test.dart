// TapHaptics and AppHaptics: a tap on something tappable plays one light
// cue, anything else stays silent, and the setting turns it all off.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/motion/tap_haptics.dart';

void main() {
  final played = <String>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.instance;
  });

  setUp(() {
    played.clear();
    AppHaptics.enabled.value = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('waffr/haptics'), (
          call,
        ) async {
          played.add(call.arguments as String);
          return null;
        });
  });

  Widget app({VoidCallback? onTap}) => MaterialApp(
    home: TapHaptics(
      child: Scaffold(
        body: Column(
          children: [
            TextButton(onPressed: onTap ?? () {}, child: const Text('button')),
            const TextButton(onPressed: null, child: Text('disabled')),
            Switch(value: false, onChanged: (_) {}),
            const SizedBox(height: 200, child: Text('plain')),
          ],
        ),
      ),
    ),
  );

  // Cues closer together than this count as one.
  Future<void> gap(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );

  testWidgets('a tap on a button or a switch ticks once', (tester) async {
    await gap(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('button'));
    await tester.pump();
    expect(played, ['tick']);

    await gap(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(played, ['tick', 'tick']);
  });

  testWidgets('empty space, disabled buttons and drags stay silent', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('plain'));
    await tester.tap(find.text('disabled'));
    await tester.drag(find.text('button'), const Offset(0, 80));
    // A long press: the finger comes up well after it went down.
    final press = await tester.startGesture(
      tester.getCenter(find.text('button')),
    );
    await press.up(timeStamp: const Duration(milliseconds: 700));
    await tester.pump();
    expect(played, isEmpty);
  });

  testWidgets('a stronger cue from the handler follows the tick', (
    tester,
  ) async {
    await gap(tester);
    await tester.pumpWidget(app(onTap: AppHaptics.success));
    await tester.tap(find.text('button'));
    await tester.pump();
    expect(played, ['tick', 'click']);
  });

  testWidgets('a second light cue right after the first is dropped', (
    tester,
  ) async {
    await gap(tester);
    await tester.pumpWidget(app(onTap: AppHaptics.selection));
    await tester.tap(find.text('button'));
    await tester.pump();
    expect(played, ['tick']);
  });

  testWidgets('the setting turns every cue off and is remembered', (
    tester,
  ) async {
    await tester.runAsync(() => AppHaptics.setEnabled(false));
    await tester.pumpWidget(app(onTap: AppHaptics.warning));
    await tester.tap(find.text('button'));
    await tester.pump();
    expect(played, isEmpty);
    final prefs = await tester.runAsync(() => AppPrefs.instance);
    expect(prefs!.getBool('haptics_enabled'), isFalse);

    await gap(tester);
    await tester.runAsync(() => AppHaptics.setEnabled(true));
    // Turning it back on answers with a cue of its own.
    expect(played, ['tick']);
  });
}
