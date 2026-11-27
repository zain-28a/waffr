// The first-run interactive tutorial: an ordered list of steps that point
// at real controls, and the controller that walks through them.
//
// The user performs each action on the real screen. Steps move on when the
// app reports what happened (TutorialController.emit: a tab was selected, a
// sheet opened or closed, a demo save), or with a "next" button on steps
// that only explain something. Sheets opened during the tutorial run in
// demo mode: they look and behave as usual but save nothing, so the
// tutorial never adds a transaction or a goal to the user's records.
//
// The overlay that draws the spotlight and the message card is
// widgets/tutorial/tutorial_layer.dart. Targets are registered with
// TutorialTargets.of(...) keys on the widgets they point at.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

/// The controls the tutorial points at. Each is wrapped in a
/// [TutorialTargets.of] key where it is built.
enum TutorialTarget {
  /// The balance card on the home tab.
  balance,

  /// The "income" quick action.
  addIncome,

  /// The "expense" quick action.
  addExpense,

  /// The spending distribution card (donut).
  spendingCard,

  /// The reports slot of the bottom bar.
  reportsTab,

  /// The savings slot of the bottom bar.
  savingsTab,

  /// The smart analysis button on the reports tab.
  smartButton,

  /// The "create goal" button (shown while there is no goal).
  createGoal,

  /// The goals panel on the savings tab (when goals already exist).
  goalsPanel,

  /// The shopping list card on the savings tab.
  shoppingList,

  /// The settings button in the header.
  settingsButton,

  /// The help row in settings.
  helpTile,
}

/// The [GlobalKey] of every [TutorialTarget], created on first use.
abstract final class TutorialTargets {
  static final Map<TutorialTarget, GlobalKey> _keys = {};

  /// The key to put on the widget for [target].
  static GlobalKey of(TutorialTarget target) => _keys.putIfAbsent(
    target,
    () => GlobalKey(debugLabel: 'tutorial-${target.name}'),
  );

  /// The on-screen rectangle of [target], or null while it is not laid out.
  static Rect? rectOf(TutorialTarget target) {
    final context = _keys[target]?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The build context of [target], if mounted.
  static BuildContext? contextOf(TutorialTarget target) =>
      _keys[target]?.currentContext;
}

/// Sheets that run without saving while the tutorial asks for them.
enum TutorialDemo {
  /// The add-income sheet.
  income,

  /// The add-expense sheet.
  expense,

  /// The create-goal sheet.
  goal,
}

/// One step of the tutorial.
class TutorialStep {
  /// Stable id, also what the saved progress refers to.
  final String id;

  /// Which of the eight topics the step belongs to (1-based), for the
  /// "3 من 8" counter.
  final int topic;

  /// Card title.
  final String title;

  /// Card text.
  final String body;

  /// The control to spotlight; null shows the card alone (a hint over a
  /// sheet or another screen the user is working in).
  final TutorialTarget? target;

  /// The tab the step happens on, selected when the step starts.
  final int? tab;

  /// The event that completes the step; null means a "next" button.
  final String? until;

  /// An event that steps back (the user closed a sheet without saving).
  final String? backOn;

  /// The sheet that runs in demo mode during this step.
  final TutorialDemo? demo;

  /// Label of the button on steps without [until].
  final String nextLabel;

  /// True for hints shown inside the sheet the user is filling in
  /// (TutorialSheetHint), so nothing covers the sheet's fields.
  final bool inline;

  /// A step.
  const TutorialStep({
    required this.id,
    required this.topic,
    required this.title,
    required this.body,
    this.target,
    this.tab,
    this.until,
    this.backOn,
    this.demo,
    this.nextLabel = 'التالي',
    this.inline = false,
  });

  /// True when the card floats over a screen without dimming it.
  bool get isHint => target == null;
}

/// The tutorial's steps, in order.
const List<TutorialStep> tutorialSteps = [
  TutorialStep(
    id: 'balance',
    topic: 1,
    target: TutorialTarget.balance,
    tab: 0,
    title: 'هذا رصيدك',
    body: 'يعرض المبلغ المتاح الآن ونسبة ما بقي من دخل الفترة، ويتحدّث مع كل دخل أو مصروف تسجّله.',
  ),
  TutorialStep(
    id: 'income-open',
    topic: 2,
    target: TutorialTarget.addIncome,
    tab: 0,
    until: 'sheet-open:income',
    demo: TutorialDemo.income,
    title: 'أضف دخلاً',
    body: 'اضغط «دخل» لتسجيل راتب أو أي مبلغ يصلك. سنجرّبه الآن دون حفظ.',
  ),
  TutorialStep(
    id: 'income-demo',
    inline: true,
    topic: 2,
    until: 'demo-saved:income',
    backOn: 'sheet-closed:income',
    demo: TutorialDemo.income,
    title: 'جرّب الإضافة',
    body: 'أدخل أي مبلغ ثم اضغط حفظ. هذه تجربة ولن يُسجَّل شيء في حسابك.',
  ),
  TutorialStep(
    id: 'expense-open',
    topic: 3,
    target: TutorialTarget.addExpense,
    tab: 0,
    until: 'sheet-open:expense',
    demo: TutorialDemo.expense,
    title: 'سجّل مصروفاً',
    body: 'اضغط «مصروف» كلما دفعت شيئاً، ولو كان مبلغاً صغيراً.',
  ),
  TutorialStep(
    id: 'expense-demo',
    inline: true,
    topic: 3,
    until: 'demo-saved:expense',
    backOn: 'sheet-closed:expense',
    demo: TutorialDemo.expense,
    title: 'اختر التصنيف',
    body: 'اختر تصنيفاً يناسب المصروف، أدخل المبلغ واضغط حفظ. التصنيف الدقيق يجعل التقارير أوضح. هذه تجربة لن تُحفظ.',
  ),
  TutorialStep(
    id: 'spending',
    topic: 4,
    target: TutorialTarget.spendingCard,
    tab: 0,
    title: 'أين يذهب مالك',
    body: 'يوزّع هذا المخطط مصروفاتك على التصنيفات. اختر المدة من أعلاه، ويظهر في وسطه أكبر تصنيف ونسبته.',
  ),
  TutorialStep(
    id: 'reports-tab',
    topic: 4,
    target: TutorialTarget.reportsTab,
    until: 'tab:1',
    title: 'التقارير',
    body: 'اضغط «التقارير» لترى صرفك عبر الأيام والأسابيع والأشهر.',
  ),
  TutorialStep(
    id: 'smart-open',
    topic: 5,
    target: TutorialTarget.smartButton,
    tab: 1,
    until: 'smart-opened',
    title: 'التحليل الذكي',
    body: 'اضغط هنا لقراءة أرقامك: اتجاهات صرفك، وتقدير نهاية الشهر، واقتراحات مبنية على بياناتك وحدها.',
  ),
  TutorialStep(
    id: 'smart-read',
    topic: 5,
    until: 'smart-closed',
    title: 'اقرأ التحليل',
    body: 'كل بطاقة تذكر إن كانت حقيقة من أرقامك أو تقديراً أو اقتراحاً. ارجع حين تنتهي لنتابع.',
  ),
  TutorialStep(
    id: 'savings-tab',
    topic: 6,
    target: TutorialTarget.savingsTab,
    until: 'tab:2',
    title: 'التوفير',
    body: 'اضغط «التوفير» لإدارة أهدافك ومدّخراتك.',
  ),
  TutorialStep(
    id: 'goal-open',
    topic: 6,
    target: TutorialTarget.createGoal,
    tab: 2,
    until: 'sheet-open:goal',
    demo: TutorialDemo.goal,
    title: 'أنشئ هدفاً',
    body: 'اضغط هنا لإنشاء هدف توفير، مثل هاتف جديد أو صندوق طوارئ.',
  ),
  TutorialStep(
    id: 'goal-demo',
    inline: true,
    topic: 6,
    until: 'demo-saved:goal',
    backOn: 'sheet-closed:goal',
    demo: TutorialDemo.goal,
    title: 'جرّب إنشاء هدف',
    body: 'اكتب اسماً ومبلغاً، واختر «مبلغ مخصص»، ثم اضغط حفظ. هذه تجربة لن تُحفظ.',
  ),
  TutorialStep(
    id: 'shopping-open',
    topic: 7,
    target: TutorialTarget.shoppingList,
    tab: 2,
    until: 'sheet-open:shopping',
    title: 'قائمة المشتريات',
    body: 'دوّن ما تنوي شراءه هنا، وحوّل كل عنصر إلى مصروف حين تشتريه.',
  ),
  TutorialStep(
    id: 'shopping-read',
    inline: true,
    topic: 7,
    until: 'sheet-closed:shopping',
    title: 'قائمتك',
    body: 'تصفّح القائمة ثم أغلقها لنتابع. أي عنصر تضيفه هنا سيُحفظ في قائمتك.',
  ),
  TutorialStep(
    id: 'settings-open',
    topic: 8,
    target: TutorialTarget.settingsButton,
    until: 'settings-opened',
    title: 'الإعدادات',
    body: 'من هنا تضبط دخلك الشهري والعملات والالتزامات وقفل التطبيق.',
  ),
  TutorialStep(
    id: 'help',
    topic: 8,
    target: TutorialTarget.helpTile,
    until: 'help-opened',
    nextLabel: 'إنهاء',
    title: 'المساعدة',
    body: 'هنا إجابات أسئلتك، ومن هنا يمكنك إعادة هذا الدليل في أي وقت.',
  ),
];

/// Number of topics shown in the step counter.
const int tutorialTopicCount = 8;

/// Walks through [tutorialSteps]; the tutorial layer listens to it.
class TutorialController extends ChangeNotifier {
  TutorialController._();

  /// The app-wide controller.
  static final TutorialController instance = TutorialController._();

  /// Prefs key: "done", or the id of the step to resume at.
  static const String progressKey = 'interactive_tutorial_v1';

  /// Value of [progressKey] once the tutorial is finished or skipped.
  static const String doneValue = 'done';

  int? _index;

  /// Selects a tab of the shell; registered by the app shell.
  ValueChanged<int>? selectTab;

  /// Steps whose target did not exist when they began (goals already set
  /// up, so there is no "create goal" button): they show with a "next"
  /// button instead of waiting for the action.
  final Set<String> _fallback = {};

  /// True while the tutorial is on screen.
  bool get active => _index != null;

  /// The current step, or null.
  TutorialStep? get step => _index == null ? null : tutorialSteps[_index!];

  /// True when [step] waits for a "next" button press.
  bool get waitsForNext {
    final current = step;
    if (current == null) return false;
    return current.until == null || _fallback.contains(current.id);
  }

  bool _skipRequested = false;

  /// True while the "leave the tutorial?" question is on screen.
  bool get skipRequested => _skipRequested;

  /// Asks whether to leave the tutorial (the layer shows the question).
  void requestSkip() {
    if (!active || _skipRequested) return;
    _skipRequested = true;
    notifyListeners();
  }

  /// Answers "keep going" to [requestSkip].
  void cancelSkip() {
    if (!_skipRequested) return;
    _skipRequested = false;
    notifyListeners();
  }

  /// True when [demo]'s sheet should save nothing right now.
  bool isDemo(TutorialDemo demo) => step?.demo == demo;

  /// Starts the tutorial on the first launch of the shell, or resumes it
  /// where it stopped, unless it was finished or skipped before.
  Future<void> maybeStart() async {
    if (active) return;
    final prefs = await AppPrefs.instance;
    final saved = prefs.getString(progressKey);
    if (saved == doneValue) return;
    final at = tutorialSteps.indexWhere((item) => item.id == saved);
    _begin(at < 0 ? 0 : _topicStart(at));
  }

  /// Starts again from the first step (from Help).
  Future<void> restart() {
    _begin(0);
    return _writing?.future ?? Future.value();
  }

  /// Moves on from a step that waits for the "next" button.
  void next() {
    if (!waitsForNext) return;
    _advance();
  }

  /// Reports something the user did. Moves the tutorial on when it is what
  /// the current step waits for, or back when the user left a demo sheet.
  void emit(String event) {
    final current = step;
    if (current == null) return;
    if (current.until == event) {
      _advance();
    } else if (current.backOn == event && _index! > 0) {
      _begin(_index! - 1);
    }
  }

  /// Ends the tutorial for good (finished or skipped).
  Future<void> finish() {
    _index = null;
    _skipRequested = false;
    _fallback.clear();
    notifyListeners();
    return _write(doneValue);
  }

  /// Marks the current step as one shown with a "next" button because its
  /// control is not on screen (the layer calls this after waiting for it).
  void useFallback() {
    final current = step;
    if (current == null || current.until == null) return;
    if (_fallback.add(current.id)) notifyListeners();
  }

  /// Clears the in-memory state (data resets and tests).
  void reset() {
    _index = null;
    _pendingWrite = null;
    _writing = null;
    _skipRequested = false;
    _fallback.clear();
    notifyListeners();
  }

  void _advance() {
    final current = _index!;
    // A step shown with "next" because its control was missing skips the
    // demo step that would have followed it.
    var next = current + 1;
    if (_fallback.contains(tutorialSteps[current].id) &&
        next < tutorialSteps.length &&
        tutorialSteps[next].target == null) {
      next++;
    }
    if (next >= tutorialSteps.length) {
      finish();
      return;
    }
    _begin(next);
  }

  void _begin(int index) {
    _index = index;
    final current = tutorialSteps[index];
    _fallback.remove(current.id);
    final tab = current.tab;
    if (tab != null) selectTab?.call(tab);
    notifyListeners();
    _write(current.id);
  }

  // Progress writes: the newest value always lands last, so an older step
  // id can never overwrite "done". A write asked for while another runs is
  // picked up by that run.
  String? _pendingWrite;
  Completer<void>? _writing;

  Future<void> _write(String value) {
    _pendingWrite = value;
    final running = _writing;
    if (running != null) return running.future;
    final done = _writing = Completer<void>();
    () async {
      try {
        while (_pendingWrite != null) {
          final next = _pendingWrite!;
          _pendingWrite = null;
          final prefs = await AppPrefs.instance;
          await prefs.setString(progressKey, next);
        }
      } finally {
        _writing = null;
        done.complete();
      }
    }();
    return done.future;
  }

  // The first step of the topic [index] belongs to, so a resumed tutorial
  // starts where its screen and sheet can be set up again.
  static int _topicStart(int index) {
    final topic = tutorialSteps[index].topic;
    return tutorialSteps.indexWhere((item) => item.topic == topic);
  }
}
