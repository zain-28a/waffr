// Insights returned by POST /ai/insights, as the app stores and shows them.

enum AiInsightTone { warning, positive, tip }

enum AiInsightsKind { weekly, monthly }

class AiInsight {
  final AiInsightTone tone;
  final String title;
  final String body;

  const AiInsight({required this.tone, required this.title, required this.body});

  static AiInsight? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title']?.toString().trim() ?? '';
    final body = raw['body']?.toString().trim() ?? '';
    if (title.isEmpty && body.isEmpty) return null;
    final tone = AiInsightTone.values.firstWhere(
      (value) => value.name == raw['tone'],
      orElse: () => AiInsightTone.tip,
    );
    return AiInsight(tone: tone, title: title, body: body);
  }

  Map<String, Object?> toJson() =>
      {'tone': tone.name, 'title': title, 'body': body};
}

class AiSavingsSuggestion {
  final double monthlyAmount;
  final String reason;

  const AiSavingsSuggestion({required this.monthlyAmount, required this.reason});

  static AiSavingsSuggestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final amount = (raw['monthly_amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return null;
    return AiSavingsSuggestion(
      monthlyAmount: amount,
      reason: raw['reason']?.toString().trim() ?? '',
    );
  }

  Map<String, Object?> toJson() =>
      {'monthly_amount': monthlyAmount, 'reason': reason};
}

class AiInsights {
  final String headline;
  final List<AiInsight> insights;
  final AiSavingsSuggestion? savingsSuggestion;
  final String summary;

  // When the app received this answer; drives the refresh policy.
  final DateTime fetchedAt;

  const AiInsights({
    required this.headline,
    required this.insights,
    required this.savingsSuggestion,
    required this.summary,
    required this.fetchedAt,
  });

  static AiInsights? fromJson(Object? raw, {DateTime? fetchedAt}) {
    if (raw is! Map) return null;
    final headline = raw['headline']?.toString().trim() ?? '';
    if (headline.isEmpty) return null;
    final list = raw['insights'];
    return AiInsights(
      headline: headline,
      insights: [
        if (list is List)
          for (final item in list)
            ?AiInsight.fromJson(item),
      ],
      savingsSuggestion: AiSavingsSuggestion.fromJson(raw['savings_suggestion']),
      summary: raw['summary']?.toString().trim() ?? '',
      fetchedAt: fetchedAt ??
          DateTime.tryParse(raw['fetched_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, Object?> toJson() => {
        'headline': headline,
        'insights': [for (final item in insights) item.toJson()],
        'savings_suggestion': savingsSuggestion?.toJson(),
        'summary': summary,
        'fetched_at': fetchedAt.toIso8601String(),
      };
}
