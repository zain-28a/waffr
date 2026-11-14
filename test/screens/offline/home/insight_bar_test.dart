// The home's way into the smart analysis: a card whose line changes every
// few seconds while the tab is on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/screens/offline/home/dashboard.dart';

import '../../../helpers/store_harness.dart';
import '../../../helpers/widget_harness.dart';

void main() {
  testWidgets('the analysis bar turns through its lines', (tester) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(setUpStores);
    // The same tree throughout, so the screen keeps its state when the tab
    // is hidden below.
    await tester.pumpWidget(
      wrapInApp(const TickerMode(enabled: true, child: HomeScreen())),
    );
    await pumpFor(tester);

    const first = 'لنبدأ معاً: سجّل مصاريفك لأحلّلها لك.';
    const second = 'التحليل جاهز حالما تبدأ بالتسجيل.';
    // With nothing logged there is no headline; the starter lines turn.
    expect(find.text(first), findsOneWidget);
    await pumpFor(tester, const Duration(milliseconds: 4600));
    expect(find.text(second), findsOneWidget);
    expect(find.text(first), findsNothing);

    // It sleeps while the tab is hidden.
    await tester.pumpWidget(
      wrapInApp(const TickerMode(enabled: false, child: HomeScreen())),
    );
    await pumpFor(tester, const Duration(seconds: 9));
    expect(find.text(second, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });
}
