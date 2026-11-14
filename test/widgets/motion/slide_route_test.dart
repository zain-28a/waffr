// The app's page transition: a page slides in from the right over the old
// one, leaves the same way, and travels sideways with the predictive back
// gesture from either screen edge.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/theme/app_theme.dart';

/// Sends one step of Android's back gesture; [edge] is 0 for a swipe from
/// the left edge and 1 for one from the right.
Future<void> _backGesture(String method, [double progress = 0, int edge = 0]) {
  final arguments =
      method == 'startBackGesture' || method == 'updateBackGestureProgress'
      ? <String, Object?>{
          'touchOffset': <double>[5, 300],
          'progress': progress,
          'swipeEdge': edge,
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
  Widget app() => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Center(child: Text('B'))),
              ),
            ),
            child: const Text('A'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('A'));
    await tester.pump();
  }

  testWidgets('the new page comes from the right; the old one moves aside', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final aRest = tester.getCenter(find.text('A')).dx;

    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Early on, B is still well to the right and A has started to the left.
    final early = tester.getCenter(find.text('B')).dx;
    expect(early, greaterThan(width / 2 + 40));
    expect(tester.getCenter(find.text('A')).dx, lessThan(aRest));

    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getCenter(find.text('B')).dx, lessThan(early));

    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('B')).dx, closeTo(width / 2, 0.5));
  });

  testWidgets('leaving plays the slide backwards', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(MaterialApp)).width;

    Navigator.of(tester.element(find.text('B'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getCenter(find.text('B')).dx, greaterThan(width / 2 + 20));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
    expect(tester.getCenter(find.text('A')).dx, closeTo(width / 2, 0.5));
  });

  testWidgets('the back gesture pulls the page aside and cancel returns it', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    final rest = tester.getCenter(find.text('B')).dx;

    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.8);
    await tester.pump();
    expect(tester.getCenter(find.text('B')).dx, greaterThan(rest + 60));

    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('B')).dx, closeTo(rest, 0.5));
  });

  testWidgets('the page travels with the finger, most of the way', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final rest = tester.getCenter(find.text('B')).dx;

    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.5);
    await tester.pump();
    expect(
      tester.getCenter(find.text('B')).dx - rest,
      closeTo(width * 0.36, 2),
    );
    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
  });

  testWidgets('a swipe from the right edge carries the page left', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    final rest = tester.getCenter(find.text('B')).dx;

    await _backGesture('startBackGesture', 0, 1);
    await _backGesture('updateBackGestureProgress', 0.6, 1);
    await tester.pump();
    final pulled = tester.getCenter(find.text('B')).dx;
    expect(pulled, lessThan(rest - 60));

    // Let go: it keeps going the same way, off the left edge.
    await _backGesture('commitBackGesture');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.getCenter(find.text('B')).dx, lessThan(pulled));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);

    // The next page comes in from the right as usual.
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(find.text('B')).dx, greaterThan(rest + 40));
    await tester.pumpAndSettle();
  });

  testWidgets('a cancelled swipe from the right edge returns the page', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    final rest = tester.getCenter(find.text('B')).dx;

    await _backGesture('startBackGesture', 0, 1);
    await _backGesture('updateBackGestureProgress', 0.6, 1);
    await tester.pump();
    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('B')).dx, closeTo(rest, 0.5));

    // And the usual way out is to the right again.
    Navigator.of(tester.element(find.text('B'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getCenter(find.text('B')).dx, greaterThan(rest + 20));
    await tester.pumpAndSettle();
  });

  testWidgets('committing the back gesture leaves the page', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.9);
    await tester.pump();
    final pulled = tester.getCenter(find.text('B')).dx;
    await _backGesture('commitBackGesture');
    // It goes on from where the finger left it; it does not jump back.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('B')).dx, greaterThanOrEqualTo(pulled));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The gesture is over for the navigator too: the next page opens and
    // answers a new gesture.
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(
      Navigator.of(tester.element(find.text('B'))).userGestureInProgress,
      isFalse,
    );
  });
}
