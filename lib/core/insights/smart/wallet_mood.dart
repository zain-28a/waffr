// The Waffr wallet's mood: one of seven smile forms picked from the same
// health score as the smart analysis. The header logo and the profile
// backdrop share one instance, so both always show the same face.
//
// The score moves with the clock (runway, days until income, this month's
// span), so a value sitting on a boundary used to flip the face back and
// forth on every refresh. A form is now kept until the score leaves its
// range by more than [SmileForm.hysteresis] points.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:waffr/core/insights/smart/insight_engine.dart';
import 'package:waffr/core/insights/smart/smart_facts_loader.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';

/// The wallet's faces, from the happiest to the saddest. Each covers the
/// scores from [minScore] up to the next form's [minScore].
enum SmileForm {
  /// 80 and above: the logo's own smile, the widest face. Also the face
  /// with nothing logged yet.
  excellent(80),

  /// 72 to 79: a full smile.
  happy(72),

  /// 65 to 71: a softer smile.
  pleased(65),

  /// 55 to 64: a slight smile.
  content(55),

  /// 45 to 54: a straight mouth.
  neutral(45),

  /// 30 to 44: corners turned slightly down.
  uneasy(30),

  /// Below 30: a clear frown.
  sad(0);

  /// Lowest score of this form.
  final int minScore;

  const SmileForm(this.minScore);

  /// Points the score must move past a form's edge before the face changes.
  static const int hysteresis = 3;

  /// First score above this form's range (101 for the top form).
  int get maxScoreExclusive => index == 0 ? 101 : values[index - 1].minScore;

  /// The form for [score] with no history.
  static SmileForm forScore(int score) =>
      values.firstWhere((form) => score >= form.minScore);

  /// The form for [score] given the [current] face: the current face stays
  /// while the score is within [hysteresis] points of its range.
  static SmileForm next(int score, SmileForm? current) {
    final target = forScore(score);
    if (current == null || current == target) return target;
    final holds =
        score >= current.minScore - hysteresis &&
        score < current.maxScoreExclusive + hysteresis;
    return holds ? current : target;
  }
}

/// App-wide holder of the current [SmileForm]. Widgets that show the face
/// call [retain] while mounted and [release] when gone; while anyone holds
/// it, store changes trigger a coalesced, serialized recompute.
class WalletMood extends ChangeNotifier {
  WalletMood._();

  /// The shared instance.
  static final WalletMood instance = WalletMood._();

  /// Delay that folds a burst of store notifications into one read.
  static const Duration coalesce = Duration(milliseconds: 250);

  /// What the score reads from.
  final Listenable _sources = Listenable.merge([
    TransactionStore.instance,
    CurrencyStore.instance,
    RecurringExpenseStore.instance,
  ]);

  SmileForm? _form;
  int? _score;
  int _holders = 0;
  bool _dirty = true;
  bool _loading = false;
  Timer? _timer;

  /// The face to show; null until the first read finishes.
  SmileForm? get form => _form;

  /// The last health score, or null with nothing logged yet.
  int? get score => _score;

  /// Starts (or keeps) watching the stores for one more holder.
  void retain() {
    if (_holders++ == 0) _sources.addListener(_onSources);
    _queue();
  }

  /// Drops one holder; the last one stops the watching.
  void release() {
    if (_holders == 0) return;
    if (--_holders > 0) return;
    _sources.removeListener(_onSources);
    _timer?.cancel();
    _timer = null;
  }

  void _onSources() {
    _dirty = true;
    _queue();
  }

  void _queue() {
    if (_holders == 0 || !_dirty || _loading || _timer?.isActive == true) {
      return;
    }
    _timer = Timer(coalesce, _read);
  }

  /// Reads the score now (tests, or after a known change).
  Future<void> refresh() {
    _dirty = true;
    _timer?.cancel();
    _timer = null;
    return _read();
  }

  Future<void> _read() async {
    _timer = null;
    if (_loading || !_dirty) return;
    _dirty = false;
    _loading = true;
    try {
      final facts = await SmartFactsLoader.load();
      // Data changed while loading: this result is stale, read again.
      if (_dirty) return;
      final empty =
          facts.expenses.isEmpty &&
          facts.incomes.isEmpty &&
          facts.savingsTransfers.isEmpty;
      final score = empty ? null : InsightEngine(facts).healthScore();
      final form = score == null
          ? SmileForm.excellent
          : SmileForm.next(score, _form);
      _score = score;
      if (form != _form) {
        _form = form;
        notifyListeners();
      }
    } finally {
      _loading = false;
      if (_dirty) _queue();
    }
  }

  /// Forgets the face and stops watching (tests).
  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    if (_holders > 0) _sources.removeListener(_onSources);
    _holders = 0;
    _form = null;
    _score = null;
    _dirty = true;
    _loading = false;
  }
}
