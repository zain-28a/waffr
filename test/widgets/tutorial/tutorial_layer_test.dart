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
import 'package:waffr/screens/shell/app_shell.dart';
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

  Future<void> start(WidgetTester tester) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(setUpStores);
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
