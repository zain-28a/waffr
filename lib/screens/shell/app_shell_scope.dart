// Lets pages inside the shell switch the bottom-navigation tab.

import 'package:flutter/widgets.dart';

/// Space a tab keeps free at the bottom of its scroll content so the last
/// card can scroll clear of the floating navigation bar.
const double kFloatingNavClearance = 88;

class AppShellTabs {
  static const int home = 0;
  static const int report = 1;
  static const int savings = 2;
}

class AppShellScope extends InheritedWidget {
  final ValueChanged<int> selectTab;

  const AppShellScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  // No-op outside the shell (e.g. widget tests that pump a page alone).
  static void selectTabOf(BuildContext context, int index) {
    context.getInheritedWidgetOfExactType<AppShellScope>()?.selectTab(index);
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      selectTab != oldWidget.selectTab;
}
