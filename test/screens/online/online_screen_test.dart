// Smoke tests for the online tab and the news sheet, and the exchange rate
// card's "coming soon" state. Network calls fail fast in tests, so the tab
// shows its offline / sign-in states.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/models/news_article.dart';
import 'package:waffr/screens/online/online_screen.dart';
import 'package:waffr/screens/online/sheets/news_sheet.dart';

import '../../helpers/store_harness.dart';
import '../../helpers/widget_harness.dart';

void main() {
  smokeTestScreen('OnlineScreen', () => const OnlineScreen());

  testWidgets('the exchange rate card says the rates are coming soon', (
    tester,
  ) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(setUpStores);
    await tester.pumpWidget(wrapInApp(const OnlineScreen()));
    await pumpFor(tester);

    expect(find.text('سعر الصرف'), findsOneWidget);
    expect(find.text('قريباً...'), findsOneWidget);
    expect(find.text('Soon...'), findsOneWidget);
    expect(find.text('شراء'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    await unmountApp(tester);
  });
  smokeTestScreen(
    'news sheet',
    () => SheetLauncher(
      open: (context) => showNewsSheet(
        context,
        articles: [
          NewsArticle(
            title: 'title',
            body: 'body',
            source: 'source',
            publishedAt: DateTime(2026, 3, 1),
          ),
        ],
      ),
    ),
    interact: openSheet,
    withSampleData: false,
  );
}
