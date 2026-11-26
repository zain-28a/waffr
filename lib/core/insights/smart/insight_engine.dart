// Turns SmartFacts into a SmartReport. Everything runs on the device.
//
// Each rule checks one pattern in the numbers and, when it applies, writes
// an insight. Titles and sentences come in a few phrasings, so the seed
// changes the wording while the findings stay the same. Cards that tell the
// same story share a topic, and only the strongest of each topic is kept.
//
// The rules live in report_insights.dart, savings_insights.dart and
// profile_insights.dart; the wording helpers in insight_phrasing.dart; the
// headline, summary and closing tip in insight_summary.dart.

import 'dart:math' as math;

import 'package:waffr/core/insights/smart/insight_phrasing.dart';
import 'package:waffr/core/insights/smart/insight_summary.dart';
import 'package:waffr/core/insights/smart/profile_insights.dart';
import 'package:waffr/core/insights/smart/report_insights.dart';
import 'package:waffr/core/insights/smart/savings_insights.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';

/// Runs the insight rules for one scope and assembles the report.
///
/// All rule groups share one [InsightPhrasing] and one random source, and
/// are called in a fixed order, so the same seed gives the same report.
class InsightEngine {
  /// The numbers to analyze.
  final SmartFacts facts;

  final InsightPhrasing _phrasing;

  /// An engine over [facts]; a fixed [seed] fixes the wording (tests).
  InsightEngine(this.facts, {int? seed})
    : _phrasing = InsightPhrasing(facts.currencySymbol, math.Random(seed));

  // Most cards a scope shows before the closing tip.
  static const Map<InsightScope, int> _limits = {
    InsightScope.reports: 8,
    InsightScope.savings: 7,
    InsightScope.profile: 8,
  };

  /// The headline, summary and ranked insight cards for [scope].
  SmartReport analyze(InsightScope scope) {
    final found = switch (scope) {
      InsightScope.reports => ReportInsights(facts, _phrasing).all(),
      InsightScope.savings => SavingsInsights(facts, _phrasing).all(),
      InsightScope.profile => ProfileInsights(facts, _phrasing).all(),
    };

    // One card per topic (the highest priority), then the cut by priority
    // alone so the findings stay the same; inside it, near-equal
    // priorities trade places between runs for variety.
    found.sort((a, b) => b.priority.compareTo(a.priority));
    final topics = <String>{};
    final distinct = [
      for (final item in found)
        if (item.topic == null || topics.add(item.topic!)) item,
    ];
    final limited = distinct.take(_limits[scope]!).toList();
    final jitter = {for (final item in limited) item.id: _phrasing.nextInt(8)};
    limited.sort(
      (a, b) =>
          (b.priority + jitter[b.id]!).compareTo(a.priority + jitter[a.id]!),
    );

    // A tip that fits the data closes the list when there is one; the
    // profile also carries the score.
    final text = InsightSummary(facts, _phrasing);
    final tip = text.tip(scope);
    if (tip != null) limited.add(tip);
    final score = scope == InsightScope.profile ? healthScore() : null;
    return SmartReport(
      scope: scope,
      headline: text.headline(scope, limited, score),
      summary: text.summary(scope),
      insights: limited,
      healthScore: score,
    );
  }

  /// Weighted 0-100 financial health score (see [ProfileInsights]).
  int healthScore() => ProfileInsights(facts, _phrasing).healthScore();

  /// A realistic monthly saving amount, or null (see [SavingsInsights]).
  double? suggestedMonthlySaving() =>
      SavingsInsights(facts, _phrasing).suggestedMonthlySaving();
}
