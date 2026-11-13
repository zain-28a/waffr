// OnboardingScreen: renders cleanly in both themes and with reduced motion.

import 'package:waffr/screens/offline/onboarding/onboarding_screen.dart';

import '../../../helpers/widget_harness.dart';

void main() {
  smokeTestScreen(
    'OnboardingScreen',
    () => OnboardingScreen(onDone: () {}),
    withSampleData: false,
  );
}
