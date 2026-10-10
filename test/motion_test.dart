import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/theme/app_motion.dart';

void main() {
  testWidgets('reduced-motion page transition returns the page as is',
      (tester) async {
    const builder = ReducedMotionPageTransitionsBuilder(
      ZoomPageTransitionsBuilder(),
    );
    const page = Text('page');
    final route = MaterialPageRoute<void>(builder: (_) => page);
    Widget? reduced;
    Widget? animated;

    Widget probe({required bool disable, required ValueSetter<Widget> out}) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: disable),
        child: Builder(
          builder: (context) {
            out(builder.buildTransitions(
              route,
              context,
              kAlwaysCompleteAnimation,
              kAlwaysDismissedAnimation,
              page,
            ));
            return const SizedBox();
          },
        ),
      );
    }

    await tester.pumpWidget(probe(disable: true, out: (w) => reduced = w));
    expect(identical(reduced, page), isTrue);

    await tester.pumpWidget(probe(disable: false, out: (w) => animated = w));
    expect(identical(animated, page), isFalse);
    route.dispose();
  });
}
