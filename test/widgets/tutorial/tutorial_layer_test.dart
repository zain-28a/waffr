// The tutorial on the real app shell: it starts once, dims everything but
// the control it points at (touches elsewhere are held back), moves on
// when the user acts, runs income and expense demos that save nothing,
// and can be skipped after a confirmation.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/l10n/waffr_material_localizations.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_theme.dart';
import 'package:waffr/core/tutorial/tutorial_controller.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/settings/help_screen.dart';
import 'package:waffr/screens/shell/app_shell.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/tutorial/tutorial_layer.dart';

import '../../helpers/store_harness.dart';
import '../../helpers/widget_harness.dart';

Widget _app() => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    WaffrMaterialLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.lightTheme,
  builder: (context, child) => Directionality(
    textDirection: TextDirection.rtl,
    child: TutorialLayer(child: child!),
  ),
  home: AppShell(
    themeNotifier: ValueNotifier(ThemeMode.light),
    onThemeChanged: () {},
    appFlowController: null,
  ),
);

void main() {
  final tutorial = TutorialController.instance;

  Future<void> start(
    WidgetTester tester, {
    String? savedStep,
    double? height,
  }) async {
    usePhoneView(tester);
    if (height != null) {
      tester.view.physicalSize = Size(kPhoneSize.width, height) * 3;
    }
    mockPlatformPlugins();
    await tester.runAsync(() async {
      await setUpStores();
      if (savedStep != null) {
        await (await AppPrefs.instance).setString(
          TutorialController.progressKey,
          savedStep,
        );
      }
    });
    await tester.pumpWidget(_app());
    await pumpFor(tester);
  }

  testWidgets('income and expense demos work with an empty ledger', (
    tester,
  ) async {
    await start(tester);
    expect(tutorial.step?.id, 'balance');
    expect(find.text('هذا رصيدك'), findsOneWidget);

    // Outside the window, touches are held back: the expense button does
    // not open its sheet.
    await tester.tap(
      find.byKey(TutorialTargets.of(TutorialTarget.addExpense)),
      warnIfMissed: false,
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('إضافة مصروف'), findsNothing);

    await tester.tap(find.text('التالي'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(tutorial.step?.id, 'income-open');

    // Inside the window the real button works.
    await tester.tap(find.byKey(TutorialTargets.of(TutorialTarget.addIncome)));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(tutorial.step?.id, 'income-demo');
    expect(find.text('جرّب الإضافة'), findsOneWidget);

    await tester.tap(find.text('5').last);
    await tester.tap(find.text('0').last);
    await tester.pump();
    // Close the keypad, then save from the sheet's header.
    await tester.tap(find.bySemanticsLabel('تم'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byIcon(AppIcons.chevronForward).last);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(tutorial.step?.id, 'expense-open');
    expect(TransactionStore.instance.incomes, isEmpty);
    expect(TransactionStore.instance.balance, 0);

    await tester.tap(find.byKey(TutorialTargets.of(TutorialTarget.addExpense)));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(tutorial.step?.id, 'expense-demo');
    expect(find.bySemanticsLabel('المصروفات المحفوظة'), findsNothing);
    expect(find.byKey(const ValueKey('__custom_action__')), findsNothing);

    await tester.tap(find.text('2').last);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('تم'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('أكبر من الرصيد المتاح'), findsNothing);
    await tester.tap(find.byIcon(AppIcons.chevronForward).last);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(tutorial.step?.id, 'spending');
    expect(find.text('إضافة مصروف'), findsNothing);
    expect(TransactionStore.instance.transactions, isEmpty);
    expect(TransactionStore.instance.balance, 0);

    await tester.runAsync(tutorial.finish);
    await pumpFor(tester);
    await tester.tap(find.byKey(TutorialTargets.of(TutorialTarget.addExpense)));
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.tap(find.text('2').last);
    await tester.pump();
    expect(find.textContaining('أكبر من الرصيد المتاح'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('the fourth step keeps Next visible beside a tall chart', (
    tester,
  ) async {
    usePhoneView(tester);
    tester.view.physicalSize = Size(kPhoneSize.width, 600) * 3;
    await tester.runAsync(() async {
      await setUpStores();
      await (await AppPrefs.instance).setString(
        TutorialController.progressKey,
        'spending',
      );
      await tutorial.maybeStart();
    });
    await tester.pumpWidget(
      wrapInApp(
        TutorialLayer(
          child: Stack(
            children: [
              Positioned(
                top: 40,
                bottom: 40,
                left: 20,
                right: 20,
                child: SizedBox(
                  key: TutorialTargets.of(TutorialTarget.spendingCard),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpFor(tester);

    final next = find.text('التالي').hitTestable();
    expect(next, findsOneWidget);
    await tester.tap(next);
    await tester.pump();
    expect(tutorial.step?.id, 'reports-tab');
    await unmountApp(tester);
  });

  testWidgets('the tutorial advances from spending through the Help screen', (
    tester,
  ) async {
    await start(tester, savedStep: 'spending', height: 640);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    Future<void> tapTarget(TutorialTarget target) async {
      final control = find.byKey(TutorialTargets.of(target)).hitTestable();
      expect(control, findsOneWidget, reason: tutorial.step?.id);
      await tester.tap(control);
      await pumpFor(tester);
    }

    expect(tutorial.step?.id, 'spending');
    expect(find.text('التالي').hitTestable(), findsOneWidget);
    await tester.tap(find.text('التالي').hitTestable());
    await pumpFor(tester);
    expect(tutorial.step?.id, 'reports-tab');
    await tapTarget(TutorialTarget.reportsTab);
    expect(tutorial.step?.id, 'smart-open');
    await tapTarget(TutorialTarget.smartButton);
    expect(tutorial.step?.id, 'smart-read');
    navigator.pop();
    await pumpFor(tester);
    expect(tutorial.step?.id, 'savings-tab');
    await tapTarget(TutorialTarget.savingsTab);
    expect(tutorial.step?.id, 'goal-open');
    await tapTarget(TutorialTarget.createGoal);
    expect(tutorial.step?.id, 'goal-demo');
    await tester.enterText(find.byType(TextField).first, 'صندوق الطوارئ');
    final amount = find.descendant(
      of: find.byType(SheetAmountField),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(amount);
    await tester.tap(amount);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('5').last);
    await tester.tap(find.bySemanticsLabel('تم'));
    await pumpFor(tester, const Duration(seconds: 1));
    final saveGoal = find.text('حفظ الهدف');
    await tester.ensureVisible(saveGoal);
    await tester.tap(saveGoal.hitTestable());
    await pumpFor(tester);
    expect(tutorial.step?.id, 'shopping-open');
    expect(TransactionStore.instance.activeGoals, isEmpty);
    await tapTarget(TutorialTarget.shoppingList);
    expect(tutorial.step?.id, 'shopping-read');
    navigator.pop();
    await pumpFor(tester);
    expect(tutorial.step?.id, 'settings-open');
    await tapTarget(TutorialTarget.settingsButton);
    expect(tutorial.step?.id, 'help');
    await tapTarget(TutorialTarget.helpTile);
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(tutorial.active, isFalse);
    await unmountApp(tester);
  });

  testWidgets('the tutorial opens Help even when its row starts offscreen', (
    tester,
  ) async {
    await start(tester, savedStep: 'help');
    tester.view.physicalSize = Size(kPhoneSize.width, 640) * 3;
    await pumpFor(tester);
    final settings = find.byKey(
      TutorialTargets.of(TutorialTarget.settingsButton),
    );
    final helpRow = find.byKey(TutorialTargets.of(TutorialTarget.helpTile));

    expect(tutorial.step?.id, 'settings-open');
    await tester.tap(settings);
    await pumpFor(tester);

    expect(tutorial.step?.id, 'help');
    expect(tutorial.waitsForNext, isFalse);
    expect(helpRow.hitTestable(), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await pumpFor(tester);
    expect(tutorial.step?.id, 'settings-open');
    await tester.tap(settings);
    await pumpFor(tester);
    await tester.tap(helpRow.hitTestable());
    await pumpFor(tester);

    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('ابدأ الدليل'), findsOneWidget);
    expect(tutorial.active, isFalse);
    await unmountApp(tester);
  });

  testWidgets('skipping asks first and is remembered', (tester) async {
    await start(tester);
    await tester.tap(find.text('تخطي الدليل'));
    await tester.pump();
    expect(find.text('الخروج من الدليل؟'), findsOneWidget);

    await tester.tap(find.text('متابعة الدليل'));
    await tester.pump();
    expect(tutorial.active, isTrue);

    await tester.tap(find.text('تخطي الدليل'));
    await tester.pump();
    await tester.tap(find.text('الخروج من الدليل'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(tutorial.active, isFalse);
    expect(find.text('هذا رصيدك'), findsNothing);
    final saved = await tester.runAsync(
      () async =>
          (await AppPrefs.instance).getString(TutorialController.progressKey),
    );
    expect(saved, TutorialController.doneValue);
    await unmountApp(tester);
  });

  testWidgets('a finished tutorial does not come back', (tester) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(() async {
      await setUpStores();
      await (await AppPrefs.instance).setString(
        TutorialController.progressKey,
        TutorialController.doneValue,
      );
    });
    await tester.pumpWidget(_app());
    await pumpFor(tester);
    expect(tutorial.active, isFalse);
    await unmountApp(tester);
  });
}
