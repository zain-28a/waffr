// Lets pages inside the shell switch the bottom-navigation tab.

import 'package:flutter/widgets.dart';

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
