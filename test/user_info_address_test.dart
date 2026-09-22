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

  testWidgets('shows one optional address field instead of three', (tester) async {
    await pumpScreen(tester);

    expect(find.text('العنوان (اختياري)'), findsOneWidget);
    expect(find.text('البلد، المدينة، الشارع'), findsOneWidget);
    expect(find.text('البلد'), findsNothing);
    expect(find.text('المدينة'), findsNothing);
    expect(find.text('الشارع'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('combines old country city street into one field', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_country': 'سوريا',
      'user_city': 'دمشق',
      'user_street': 'المزة',
    });

    await pumpScreen(tester);

    expect(tester.widget<TextField>(find.byType(TextField).last).controller?.text,
        'سوريا، دمشق، المزة');
  });

  testWidgets('continue works without an address', (tester) async {
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

    expect(continued, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_address'), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('saves country city street as one address', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_email': 'a@b.com',
      'user_name': 'زين',
      'user_birthdate': DateTime(2000, 1, 1).toIso8601String(),
    });

    var continued = false;
    await pumpScreen(tester, onContinue: () => continued = true);

    await tester.enterText(
      find.byType(TextField).last,
      'سوريا، دمشق، المزة',
    );
    await tester.ensureVisible(find.text('متابعة'));
    await tester.tap(find.text('متابعة'));
    await tester.pump();

    expect(continued, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_address'), 'سوريا، دمشق، المزة');
    expect(prefs.getString('user_country'), isNull);
    expect(prefs.getString('user_city'), isNull);
    expect(prefs.getString('user_street'), isNull);
    await tester.pump(const Duration(seconds: 2));
  });
}
