// The balance card's currency flip: the card leans with a vertical drag,
// turns over the way it was swiped, and lies flat again on a short drag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/screens/offline/home/dashboard.dart';

import '../../../helpers/store_harness.dart';
import '../../../helpers/widget_harness.dart';

/// The card's turn, read from the flip transform: positive when the top
/// edge comes forward (a downward swipe), negative for an upward one, and
/// zero when the card lies flat.
double _turn(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(
    find.ancestor(
      of: find.text('الرصيد الحالي').first,
      matching: find.byType(Transform),
    ),
  );
  for (final transform in transforms) {
    final matrix = transform.transform;
    // The flip is the one with this perspective.
    if ((matrix.entry(3, 2) / 0.0008 - matrix.entry(2, 2)).abs() < 0.001 &&
        matrix.entry(2, 1).abs() > 0.0001) {
      return matrix.entry(2, 1);
    }
  }
  return 0;
}

void main() {
  Future<void> open(WidgetTester tester, {bool reduced = false}) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(() async {
      await setUpStores();
      await CurrencyStore.instance.addCurrency('USD');
    });
    await tester.pumpWidget(
      wrapInApp(const HomeScreen(), reduceMotion: reduced),
    );
    await pumpFor(tester);
  }

  Finder card() => find.text('الرصيد الحالي').first;

  /// Lets the store save the new active currency (real I/O), then builds.
  Future<void> switched(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }

  testWidgets('the card leans the way it is dragged', (tester) async {
    await open(tester);
    expect(_turn(tester), 0);

    final down = await tester.startGesture(tester.getCenter(card()));
    await down.moveBy(const Offset(0, 30));
    await down.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(_turn(tester), greaterThan(0));
    // Back the other way, past where it started.
    await down.moveBy(const Offset(0, -130));
    await tester.pump();
    expect(_turn(tester), lessThan(0));
    // Let go near flat: no flip.
    await down.moveBy(const Offset(0, 60));
    await down.up();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(_turn(tester), 0);
    expect(CurrencyStore.instance.activeCode, 'SYP');
    await unmountApp(tester);
  });

  for (final (name, offset, sign) in [
    ('down', const Offset(0, 300), 1),
    ('up', const Offset(0, -300), -1),
  ]) {
    testWidgets('a swipe $name turns the card over $name', (tester) async {
      await open(tester);
      await tester.fling(card(), offset, 900);
      await switched(tester);
      // The first part of the flip: the old face turning away the way the
      // finger went.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      expect(CurrencyStore.instance.activeCode, 'USD');
      expect(_turn(tester) * sign, greaterThan(0));

      // Past edge-on the new face swings in from the other side.
      await tester.pump(const Duration(milliseconds: 330));
      expect(_turn(tester) * sign, lessThan(0));

      await pumpFor(tester, const Duration(seconds: 1));
      expect(_turn(tester), 0);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });
  }

  testWidgets('reduced motion switches the currency without a flip', (
    tester,
  ) async {
    await open(tester, reduced: true);
    await tester.fling(card(), const Offset(0, -300), 900);
    await switched(tester);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(CurrencyStore.instance.activeCode, 'USD');
    expect(_turn(tester), 0);
    await unmountApp(tester);
  });
}
