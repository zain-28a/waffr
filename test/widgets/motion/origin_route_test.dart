// OriginPageRoute: the page grows out of the tapped widget, is the plain
// page at rest, folds back on pop, and jumps with reduced motion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/widgets/motion/origin_route.dart';

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
