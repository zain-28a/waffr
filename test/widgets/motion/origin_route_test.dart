// OriginPageRoute: the page grows out of the tapped widget, is the plain
// page at rest, shrinks back into it on pop or on the back gesture, leaves
// the page below in place, and jumps with reduced motion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/widgets/motion/origin_route.dart';

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
  Widget app({bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: Builder(
            builder: (context) => SizedBox(
              width: 80,
              height: 40,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  originPageRoute<void>(
                    context,
                    (_) => const Scaffold(body: Center(child: Text('page'))),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('grows from the origin, rests full size, folds back', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final screen = tester.getSize(find.byType(MaterialApp));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Early in the transition the page is still a small clipped box.
    final early = tester.getSize(find.byType(ClipRRect).last);
    expect(early.width, lessThan(screen.width * 0.8));

    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold).last), screen);

    Navigator.of(tester.element(find.text('page'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('page'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('page'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page below stays where it is', (tester) async {
    await tester.pumpWidget(app());
    final rest = tester.getCenter(find.text('open'));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getCenter(find.text('open')), rest);
    await tester.pumpAndSettle();
  });

  testWidgets('closing ends on the widget it opened from', (tester) async {
    await tester.pumpWidget(app());
    final origin = tester.getRect(find.byType(SizedBox).last);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('page'))).pop();
    await tester.pump();
    // Just before the end the page is a small box over the origin.
    await tester.pump(const Duration(milliseconds: 385));
    final late = tester.getRect(find.byType(ClipRRect).last);
    expect(late.width, lessThan(origin.width * 2));
    expect(late.overlaps(origin), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('the back gesture shrinks the page toward its origin', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final screen = tester.getSize(find.byType(MaterialApp));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.9);
    await tester.pump();
    final pulled = tester.getSize(find.byType(ClipRRect).last);
    expect(pulled.width, lessThan(screen.width - 20));
    expect(pulled.width, greaterThan(screen.width * 0.6));

    await _backGesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold).last), screen);

    await _backGesture('startBackGesture');
    await _backGesture('updateBackGestureProgress', 0.9);
    await tester.pump();
    final held = tester.getSize(find.byType(ClipRRect).last).width;
    await _backGesture('commitBackGesture');
    // It shrinks on from where the finger left it; it does not grow back.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSize(find.byType(ClipRRect).last).width,
      lessThanOrEqualTo(held),
    );
    await tester.pumpAndSettle();
    expect(find.text('page'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caller that fills the screen gets the plain transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  originPageRoute<void>(
                    context,
                    (_) => const Scaffold(body: Text('page')),
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
    await tester.pump();
    final route = ModalRoute.of(
      tester.element(find.text('page', skipOffstage: false)),
    );
    expect(route, isNot(isA<OriginPageRoute<void>>()));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion opens without the origin transition', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduced: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
