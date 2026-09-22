import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/screens/offline/user_info/user_info_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    VoidCallback? onContinue,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
        home: UserInfoScreen(onContinue: onContinue ?? () {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows required country and city with optional street', (tester) async {
    await pumpScreen(tester);

    expect(find.text('البلد'), findsOneWidget);
    expect(find.text('المدينة'), findsOneWidget);
    expect(find.text('الشارع (اختياري)'), findsOneWidget);
    expect(find.text('العنوان (اختياري)'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(5));
  });

  testWidgets('loads split address fields from saved values', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_country': 'سوريا',
      'user_city': 'دمشق',
      'user_street': 'المزة',
    });

    await pumpScreen(tester);

    expect(tester.widget<TextField>(find.byType(TextField).at(2)).controller?.text,
        'سوريا');
    expect(tester.widget<TextField>(find.byType(TextField).at(3)).controller?.text,
        'دمشق');
    expect(tester.widget<TextField>(find.byType(TextField).at(4)).controller?.text,
        'المزة');
  });

  testWidgets('continue stays blocked without country or city', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_email': 'a@b.com',
      'user_name': 'زين',
      'user_birthdate': DateTime(2000, 1, 1).toIso8601String(),
    });

    var continued = false;
    await pumpScreen(tester, onContinue: () => continued = true);

    await tester.ensureVisible(find.text('متابعة'));
    await tester.tap(find.text('متابعة'));
    await tester.pump();

    expect(continued, isFalse);
  });

  testWidgets('continue works with country and city only', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_email': 'a@b.com',
      'user_name': 'زين',
      'user_birthdate': DateTime(2000, 1, 1).toIso8601String(),
    });

    var continued = false;
    await pumpScreen(tester, onContinue: () => continued = true);

    await tester.enterText(find.byType(TextField).at(2), 'سوريا');
    await tester.enterText(find.byType(TextField).at(3), 'دمشق');
    await tester.pump();
    await tester.ensureVisible(find.text('متابعة'));
    await tester.tap(find.text('متابعة'));
    await tester.pump();

    expect(continued, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_country'), 'سوريا');
    expect(prefs.getString('user_city'), 'دمشق');
    expect(prefs.getString('user_street'), isNull);
    expect(prefs.getString('user_address'), 'سوريا، دمشق');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('saves street when the user enters it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_email': 'a@b.com',
      'user_name': 'زين',
      'user_birthdate': DateTime(2000, 1, 1).toIso8601String(),
    });

    var continued = false;
    await pumpScreen(tester, onContinue: () => continued = true);

    await tester.enterText(find.byType(TextField).at(2), 'سوريا');
    await tester.enterText(find.byType(TextField).at(3), 'دمشق');
    await tester.enterText(find.byType(TextField).at(4), 'المزة');
    await tester.pump();
    await tester.ensureVisible(find.text('متابعة'));
    await tester.tap(find.text('متابعة'));
    await tester.pump();

    expect(continued, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_country'), 'سوريا');
    expect(prefs.getString('user_city'), 'دمشق');
    expect(prefs.getString('user_street'), 'المزة');
    expect(prefs.getString('user_address'), 'سوريا، دمشق، المزة');
    await tester.pump(const Duration(seconds: 2));
  });
}
