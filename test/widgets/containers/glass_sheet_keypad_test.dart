// Glass sheets follow Android's predictive back gesture: the sheet sinks
// while the gesture is in progress, returns when it is cancelled and
// closes when it is committed. The amount keypad docks under the sheet,
// edits the field, and offers quick amounts the user can change.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';

Future<void> _backGesture(String method, [double progress = 0]) {
  final arguments =
      method == 'startBackGesture' || method == 'updateBackGestureProgress'
      ? <String, Object?>{
          'touchOffset': <double>[5, 300],
          'progress': progress,
          'swipeEdge': 0,
        }
      : null;
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

void main() {
  // Prefs are opened once here, outside any test's fake clock, so later
  // tests never wait on a future that an earlier test's clock owns.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.instance;
    await QuickAmounts.instance.ensureLoaded();
  });

  Future<void> open(
    WidgetTester tester, {
    TextEditingController? amount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGlassSheet<void>(
                  context: context,
                  builder: (_) => GlassSheetBody(
                    children: [
                      const GlassSheetHeader(title: 'title', subtitle: 'sub'),
                      if (amount != null)
                        SheetAmountField(
                          label: 'amount',
                          controller: amount,
                          autofocus: true,
                        )
                      else
                        const SizedBox(height: 300),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('title'), findsOneWidget);
  }

  testWidgets('the sheet sinks with the back gesture and returns on cancel', (
    tester,
  ) async {
    await open(tester);
    final rest = tester.getTopLeft(find.text('title')).dy;

    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.8);
    await tester.pump();
    expect(tester.getTopLeft(find.text('title')).dy, greaterThan(rest + 20));

    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('title')).dy, closeTo(rest, 0.5));
  });

  testWidgets('committing the back gesture closes the sheet', (tester) async {
    await open(tester);
    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.9);
    await tester.pump();
    await _backGesture('commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('title'), findsNothing);
  });

  testWidgets('the keypad types, adds, deletes and closes', (tester) async {
    final amount = TextEditingController();
    addTearDown(amount.dispose);
    await open(tester, amount: amount);

    // Autofocus opened the keypad.
    expect(find.bySemanticsLabel('تم'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('5'));
    // The last '0' is the key; the first is the field's hint.
    await tester.tap(find.text('0').last);
    await tester.pump();
    expect(amount.text, '1,250');

    await tester.tap(find.bySemanticsLabel('حذف'));
    await tester.pump();
    expect(amount.text, '125');

    await tester.longPress(find.bySemanticsLabel('حذف'));
    await tester.pump();
    expect(amount.text, isEmpty);

    await tester.tap(find.bySemanticsLabel('تم'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('تم'), findsNothing);
  });

  testWidgets('the keypad docks at the bottom, below the sheet', (
    tester,
  ) async {
    final amount = TextEditingController();
    addTearDown(amount.dispose);
    await open(tester, amount: amount);

    final screen = tester.getSize(find.byType(MaterialApp));
    final done = tester.getRect(find.bySemanticsLabel('تم'));
    final field = tester.getRect(find.byType(SheetAmountField));
    // The last row of keys sits at the bottom edge, under the field.
    expect(done.bottom, greaterThan(screen.height - 40));
    expect(done.top, greaterThan(field.bottom));
  });

  testWidgets('quick amounts start as banknote values and add up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await (await AppPrefs.instance).clear();
      QuickAmounts.instance.resetCache();
      await QuickAmounts.instance.ensureLoaded();
    });
    final amount = TextEditingController();
    addTearDown(amount.dispose);
    await open(tester, amount: amount);

    for (final value in ['+10', '+25', '+50', '+100', '+200', '+500']) {
      expect(find.text(value), findsOneWidget);
    }
    await tester.tap(find.text('+200'));
    await tester.tap(find.text('+50'));
    await tester.pump();
    expect(amount.text, '250');
  });

  test('quick amounts can be edited, are kept, and reset', () async {
    SharedPreferences.setMockInitialValues({});
    await (await AppPrefs.instance).clear();
    final store = QuickAmounts.instance..resetCache();
    await store.ensureLoaded();
    expect(store.values, [10, 25, 50, 100, 200, 500]);
    expect(store.isDefault, isTrue);

    // Full row: nothing is added until one is removed.
    expect(await store.add(1000), isFalse);
    await store.remove(25);
    expect(await store.add(1000), isTrue);
    expect(await store.add(1000), isFalse, reason: 'duplicate');
    expect(await store.add(0), isFalse);
    expect(store.values, [10, 50, 100, 200, 500, 1000]);
    expect(store.isDefault, isFalse);

    // Survives a restart.
    store.resetCache();
    await store.ensureLoaded();
    expect(store.values, [10, 50, 100, 200, 500, 1000]);

    await store.reset();
    expect(store.values, QuickAmounts.defaults);
  });
}
