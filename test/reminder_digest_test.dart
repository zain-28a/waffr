import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/insights/smart/reminder_digest.dart';
import 'package:waffr/core/insights/smart/smart_facts.dart';
import 'package:waffr/data/models/transaction.dart';

final DateTime _now = DateTime(2026, 10, 20, 12);
int _ids = 0;

WaffrTransaction _expense(double amount, DateTime date, {String category = 'طعام'}) =>
    WaffrTransaction(
      id: 'e${_ids++}',
      type: TransactionType.expense,
      amount: amount,
      dateTime: date,
      category: category,
    );

SmartFacts _facts({
  List<WaffrTransaction> expenses = const [],
  List<GoalFact> goals = const [],
  List<ObligationFact> obligations = const [],
  double balance = 500,
}) =>
    SmartFacts(
      now: _now,
      currencySymbol: 'ل.س',
      expenses: expenses,
      incomes: const [],
      savingsTransfers: const [],
      balance: balance,
      maxBalance: 1000,
      monthlyIncome: 1000,
      incomeFrequency: RecurringFrequency.monthly,
      hasRecurringIncome: true,
      savingsBalance: 0,
      goals: goals,
      completedGoals: 0,
      obligations: obligations,
      pendingShopping: 0,
      streakCount: 1,
      usageStartedAt: null,
    );

// Words that would make a reminder read as "come back to the app".
const _nudges = ['افتح', 'عُد', 'ادخل', 'سجّل', 'التطبيق'];

void main() {
  final fireAt = DateTime(2026, 10, 22, 20, 30);

  test('an obligation due soon comes first, counted from the fire date', () {
    final digest = ReminderDigest(_facts(obligations: [
      ObligationFact(
        name: 'إيجار',
        amount: 300,
        monthlyEquivalent: 300,
        nextDueAt: DateTime(2026, 10, 25),
      ),
    ]));

    final first = digest.candidates(fireAt).first;

    expect(first.kind, 'obligation');
    expect(first.title, '«إيجار» مستحق بعد 3 أيام');
    expect(first.body, 'المبلغ 300 ل.س.');
  });

  test('balance reminder counts the days left at fire time', () {
    final balance = ReminderDigest(_facts())
        .candidates(fireAt)
        .firstWhere((item) => item.kind == 'balance');

    // Income on 1 Nov: 12 days from the 20th, 10 from the 22nd.
    expect(balance.body, contains('10 أيام'));
  });

  test('category growth and goal progress read as facts', () {
    final texts = ReminderDigest(_facts(
      expenses: [
        for (var d = 1; d <= 10; d++) _expense(50, DateTime(2026, 10, d), category: 'ترفيه'),
        for (var d = 1; d <= 10; d++) _expense(20, DateTime(2026, 9, d), category: 'ترفيه'),
      ],
      goals: [
        GoalFact(
          id: 'g',
          name: 'سفر',
          target: 1000,
          saved: 650,
          createdAt: DateTime(2026, 9, 1),
          plannedMonths: 6,
        ),
      ],
    )).candidates(fireAt);

    final category = texts.firstWhere((item) => item.kind == 'category');
    final goal = texts.firstWhere((item) => item.kind == 'goal');
    expect(category.title, contains('الترفيه'));
    expect(goal.title, contains('«سفر»'));
    expect(goal.body, 'بقي 350 ل.س على الهدف.');
  });

  test('no reminder text asks the user to open the app', () {
    final digest = ReminderDigest(_facts(
      expenses: [
        for (var d = 1; d <= 20; d++) _expense(30, DateTime(2026, 10, d)),
        for (var d = 1; d <= 20; d++) _expense(15, DateTime(2026, 9, d)),
      ],
      obligations: [
        ObligationFact(
          name: 'إنترنت',
          amount: 50,
          monthlyEquivalent: 50,
          nextDueAt: DateTime(2026, 10, 23),
        ),
      ],
    ));
    final all = [...digest.candidates(fireAt), ?digest.weekly()];

    expect(all, isNotEmpty);
    for (final text in all) {
      for (final word in _nudges) {
        expect('${text.title} ${text.body}', isNot(contains(word)));
      }
    }
  });

  test('weekly summary compares with last week', () {
    final weekly = ReminderDigest(_facts(expenses: [
      _expense(100, DateTime(2026, 10, 18)),
      _expense(50, DateTime(2026, 10, 11)),
    ])).weekly();

    expect(weekly!.title, 'صرفك هذا الأسبوع 100 ل.س');
    expect(weekly.body, contains('أكثر'));
  });
}
