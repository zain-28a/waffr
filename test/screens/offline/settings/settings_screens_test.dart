// Smoke tests for the settings screen and every screen it opens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/screens/offline/settings/about_screen.dart';
import 'package:waffr/screens/offline/settings/backup_screen.dart';
import 'package:waffr/screens/offline/settings/account_screen.dart';
import 'package:waffr/screens/offline/settings/ai_permissions_screen.dart';
import 'package:waffr/screens/offline/settings/change_password_screen.dart';
import 'package:waffr/screens/offline/settings/help_screen.dart';
import 'package:waffr/screens/offline/settings/privacy_security_screen.dart';
import 'package:waffr/screens/offline/settings/settings_screen.dart';

import '../../../helpers/widget_harness.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    smokeTestScreen(
      'SettingsScreen (${mode.name} notifier)',
      () => SettingsScreen(
        themeNotifier: ValueNotifier(mode),
        onThemeChanged: () {},
        appFlowController: null,
      ),
    );
  }
  smokeTestScreen('PrivacySecurityScreen', () => const PrivacySecurityScreen());
  smokeTestScreen('AccountScreen', () => const AccountScreen());
  smokeTestScreen('AIPermissionsScreen', () => const AIPermissionsScreen());
  smokeTestScreen('ChangePasswordScreen', () => const ChangePasswordScreen());
  smokeTestScreen('HelpScreen', () => const HelpScreen());
  smokeTestScreen('AboutScreen', () => const AboutScreen());
  smokeTestScreen(
    'BackupScreen',
    () => const BackupScreen(),
    interact: (tester) async {
      // A guest is told the data lives on this phone only.
      expect(find.textContaining('على هذا الهاتف فقط'), findsOneWidget);
      // A short passphrase is refused before anything is sealed.
      await tester.enterText(find.byType(TextField).at(0), 'short');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.tap(find.text('حفظ النسخة'));
      await tester.pump();
      expect(find.textContaining('10 أحرف على الأقل'), findsWidgets);
      // Mismatched passphrases are refused too.
      await tester.enterText(
        find.byType(TextField).at(0),
        'a long passphrase 1',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'a long passphrase 2',
      );
      await tester.tap(find.text('حفظ النسخة'));
      await tester.pump();
      expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
    },
  );
}
