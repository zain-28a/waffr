// Glass sheets follow Android's predictive back gesture: the sheet sinks
// while the gesture is in progress, returns when it is cancelled and
// closes when it is committed. The amount keypad edits the field.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
