// What the smart analysis produces: a headline, a short summary, and a
// ranked list of insights for one area of the app.

import 'package:flutter/material.dart';

// Which screen asked; each scope looks at a different slice of the data.
enum InsightScope { reports, savings, profile }

extension InsightScopeLabel on InsightScope {
  String get label => switch (this) {
        InsightScope.reports => 'المصاريف',
        InsightScope.savings => 'التوفير',
        InsightScope.profile => 'نظرة شاملة',
      };

  IconData get icon => switch (this) {
        InsightScope.reports => Icons.bar_chart_rounded,
        InsightScope.savings => Icons.savings_outlined,
        InsightScope.profile => Icons.person_outline_rounded,
      };
}

enum InsightTone { warning, positive, tip, info }

// Something the user can do straight from an insight card.
enum InsightAction {
  addExpense,
  addIncome,
  createGoal,
  manualSave,
  obligations,
  shoppingList,
  expenseHistory,
}

extension InsightActionLabel on InsightAction {
  String get label => switch (this) {
        InsightAction.addExpense => 'سجّل مصروف',
        InsightAction.addIncome => 'أضف دخل',
        InsightAction.createGoal => 'أنشئ هدف',
        InsightAction.manualSave => 'وفّر الآن',
        InsightAction.obligations => 'افتح الالتزامات',
        InsightAction.shoppingList => 'قائمة المشتريات',
        InsightAction.expenseHistory => 'سجل المصروفات',
      };
}

class SmartInsight {
  // Stable per rule, so the screen can key cards and tests can find them.
  final String id;
  final InsightTone tone;
  final IconData icon;
  final String title;
  final String body;

  // The numbers behind the insight, shown when the card is expanded.
  final String? detail;

  // Higher shows first.
  final int priority;
  final InsightAction? action;

  const SmartInsight({
    required this.id,
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.detail,
    this.priority = 50,
    this.action,
  });
}

class SmartReport {
  final InsightScope scope;
  final String headline;
  final String summary;
  final List<SmartInsight> insights;

  // 0-100 financial health, profile scope only.
  final int? healthScore;

  const SmartReport({
    required this.scope,
    required this.headline,
    required this.summary,
    required this.insights,
    this.healthScore,
  });
}
