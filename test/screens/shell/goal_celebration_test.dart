// The shell celebrates a savings goal that completes while the app is open,
// once, and the overlay removes itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/data/models/savings_goal.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/shell/app_shell.dart';
import 'package:waffr/widgets/brand/goal_celebration.dart';

import '../../helpers/store_harness.dart';
import '../../helpers/widget_harness.dart';

void main() {
  final store = TransactionStore.instance;

  Future<void> boot(
    WidgetTester tester, {
    required bool completedBefore,
  }) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(() async {
      await setUpStores();
      await store.addIncome(amount: 1000);
      await store.createGoal(
        name: 'سفر',
        targetAmount: completedBefore ? 100 : 500,
        duration: GoalDurationPreset.month,
        allocatePercent: 10,
      );
      await store.saveManually(200);
    });
    await tester.pumpWidget(
      wrapInApp(
        AppShell(
          themeNotifier: ValueNotifier(ThemeMode.light),
          onThemeChanged: () {},
          appFlowController: null,
        ),
      ),
    );
    await pumpFor(tester);
  }

  testWidgets('a goal completed while open is celebrated once', (tester) async {
    await boot(tester, completedBefore: false);
    expect(find.byType(GoalCelebrationOverlay), findsNothing);

    await tester.runAsync(
      () => store.updateGoal(store.activeGoals.first.id, targetAmount: 150),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GoalCelebrationOverlay), findsOneWidget);
    expect(find.text('تحقّق هدفك!'), findsOneWidget);
    expect(find.text('سفر'), findsWidgets);

    // The sequence ends and the overlay leaves on its own.
    await pumpFor(tester, const Duration(seconds: 5));
    expect(find.byType(GoalCelebrationOverlay), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('a goal that was already complete is not celebrated', (
    tester,
  ) async {
    await boot(tester, completedBefore: true);
    expect(store.allCompletedGoals, hasLength(1));
    expect(find.byType(GoalCelebrationOverlay), findsNothing);
    await unmountApp(tester);
  });
}
