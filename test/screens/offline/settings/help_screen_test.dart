// The help center: its topics cover every feature area, search folds Arabic
// letter variants and needs every word, questions open in place, and the
// tutorial can be started again from the top card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/tutorial/tutorial_controller.dart';
import 'package:waffr/screens/offline/settings/help_content.dart';
import 'package:waffr/screens/offline/settings/help_screen.dart';

import '../../../helpers/store_harness.dart';
import '../../../helpers/widget_harness.dart';

void main() {
  test('every feature area has its topic, with complete answers', () {
    final titles = helpSections.map((section) => section.title).toList();
    for (final topic in [
      'البدء',
      'الرصيد والدخل',
      'المصروفات والتصنيفات',
      'الالتزامات المتكررة',
      'التقارير والمخططات',
      'التحليل الذكي',
      'التوفير والأهداف',
      'قائمة المشتريات',
      'الإشعارات',
      'أدوات الشاشة الرئيسية',
      'العملات',
      'الحساب والمزامنة',
      'الخصوصية والأمان',
      'حل المشكلات',
    ]) {
      expect(titles, contains(topic));
    }
    final questions = [
      for (final section in helpSections)
        for (final entry in section.items) entry.question,
    ];
    expect(questions.toSet(), hasLength(questions.length));
    for (final section in helpSections) {
      expect(section.items, isNotEmpty, reason: section.title);
      for (final entry in section.items) {
        expect(entry.answer.length, greaterThan(40), reason: entry.question);
        expect(entry.answer, isNot(contains('  ')));
      }
    }
  });

  test('search folds letter variants and needs every word', () {
    expect(foldArabic('الإشعارات'), foldArabic('الاشعارات'));
    expect(foldArabic('قائمة'), foldArabic('قائمه'));
    final widgets = searchHelp('الادوات', helpSections);
    expect(widgets, isNotEmpty);
    expect(widgets.first.topic, 'أدوات الشاشة الرئيسية');
    expect(searchHelp('هدف توفير', helpSections), isNotEmpty);
    expect(searchHelp('كلمةغيرموجودة', helpSections), isEmpty);
    expect(searchHelp('   ', helpSections), isEmpty);
  });

  testWidgets('searching narrows the list and a question opens', (
    tester,
  ) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(setUpStores);
    await tester.pumpWidget(wrapInApp(const HelpScreen()));
    await pumpFor(tester);

    await tester.enterText(find.byType(TextField), 'أخفي المبالغ');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('نتيجة واحدة'), findsOneWidget);
    // A single result is open already.
    expect(find.textContaining('تظهر نقاط بدل المبالغ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'زززز');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('لا توجد أسئلة تطابق'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('ما هو وفّر؟'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      find.textContaining('تُحفظ بياناتك على جهازك أولاً'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('the tutorial starts again from the top card', (tester) async {
    usePhoneView(tester);
    mockPlatformPlugins();
    await tester.runAsync(() async {
      await setUpStores();
      await TutorialController.instance.finish();
    });
    await tester.pumpWidget(wrapInApp(const HelpScreen()));
    await pumpFor(tester);
    expect(TutorialController.instance.active, isFalse);
    await tester.tap(find.text('ابدأ الدليل'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(TutorialController.instance.step?.id, 'balance');
    await unmountApp(tester);
  });
}
