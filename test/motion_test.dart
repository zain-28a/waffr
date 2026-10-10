import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/widgets/motion/animated_number_text.dart';
import 'package:waffr/widgets/motion/fade_slide_in.dart';

Widget _host(Widget child, {bool reduced = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

double _opacityOf(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.descendant(
          of: find.byType(FadeSlideIn),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
}

void main() {
  String format(double value) => value.round().toString();

  testWidgets('number text shows the first value without counting',
      (tester) async {
    await tester.pumpWidget(
      _host(AnimatedNumberText(value: 120, format: format)),
    );
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('number text counts toward a new value', (tester) async {
    await tester.pumpWidget(
      _host(AnimatedNumberText(value: 0, format: format)),
    );
    await tester.pumpWidget(
      _host(AnimatedNumberText(value: 100, format: format)),
    );
    await tester.pump(AppMotion.countUp ~/ 3);
    final midway = int.parse(
      tester.widget<Text>(find.byType(Text)).data!,
    );
    expect(midway, greaterThan(0));
    expect(midway, lessThan(100));

    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('number text jumps when reduced motion is on', (tester) async {
    await tester.pumpWidget(
      _host(AnimatedNumberText(value: 0, format: format), reduced: true),
    );
    await tester.pumpWidget(
      _host(AnimatedNumberText(value: 100, format: format), reduced: true),
    );
    await tester.pump();
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('fade-slide-in starts hidden and settles visible',
      (tester) async {
    await tester.pumpWidget(_host(const FadeSlideIn(child: Text('row'))));
    expect(_opacityOf(tester), 0);

    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1);
  });

  testWidgets('fade-slide-in waits for its delay', (tester) async {
    await tester.pumpWidget(
      _host(
        const FadeSlideIn(
          delay: Duration(milliseconds: 90),
          child: Text('row'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacityOf(tester), 0);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1);
  });

  testWidgets('fade-slide-in is at rest when disabled or reduced',
      (tester) async {
    await tester.pumpWidget(
      _host(const FadeSlideIn(enabled: false, child: Text('row'))),
    );
    expect(_opacityOf(tester), 1);

    await tester.pumpWidget(
      _host(
        const FadeSlideIn(key: ValueKey('reduced'), child: Text('row')),
        reduced: true,
      ),
    );
    expect(_opacityOf(tester), 1);
  });

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
