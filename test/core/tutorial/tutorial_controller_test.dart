// TutorialController: starting once, moving on by "next" or by the events
// the app reports, stepping back when a demo sheet is closed, demo flags,
// the fallback for a control that is not on screen, resuming at the start
// of a topic, and the saved "done" state.

import 'package:flutter_test/flutter_test.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/tutorial/tutorial_controller.dart';

import '../../helpers/store_harness.dart';

void main() {
  final tutorial = TutorialController.instance;

  setUp(() async {
    await setUpStores();
  });

  Future<String?> saved() async =>
      (await AppPrefs.instance).getString(TutorialController.progressKey);

  test('starts on the balance and moves on with next', () async {
    final tabs = <int>[];
    tutorial.selectTab = tabs.add;
    await tutorial.maybeStart();
    expect(tutorial.step!.id, 'balance');
    expect(tutorial.waitsForNext, isTrue);
    expect(tabs, [0], reason: 'the step selects its tab');

    tutorial.next();
    expect(tutorial.step!.id, 'income-open');
    expect(tutorial.waitsForNext, isFalse);
    tutorial.next(); // ignored: this step waits for the sheet
    expect(tutorial.step!.id, 'income-open');
  });

  test('events move on, closing a demo sheet steps back', () async {
    await tutorial.maybeStart();
    tutorial.next();
    expect(tutorial.isDemo(TutorialDemo.income), isTrue);
    tutorial.emit('sheet-open:income');
    expect(tutorial.step!.id, 'income-demo');
    expect(tutorial.isDemo(TutorialDemo.income), isTrue);
    expect(tutorial.isDemo(TutorialDemo.expense), isFalse);

    tutorial.emit('sheet-closed:income');
    expect(tutorial.step!.id, 'income-open');

    tutorial.emit('sheet-open:income');
    tutorial.emit('demo-saved:income');
    expect(tutorial.step!.id, 'expense-open');
    // The sheet closing after a demo save does not step back.
    tutorial.emit('sheet-closed:income');
    expect(tutorial.step!.id, 'expense-open');
    // Unrelated events change nothing.
    tutorial.emit('tab:3');
    expect(tutorial.step!.id, 'expense-open');
  });

  test(
    'a missing control turns the step into next and skips its demo',
    () async {
      await tutorial.maybeStart();
      while (tutorial.step!.id != 'goal-open') {
        final step = tutorial.step!;
        if (step.until == null) {
          tutorial.next();
        } else {
          tutorial.emit(step.until!);
        }
      }
      expect(tutorial.waitsForNext, isFalse);
      tutorial.useFallback();
      expect(tutorial.waitsForNext, isTrue);
      tutorial.next();
      expect(tutorial.step!.id, 'shopping-open', reason: 'goal-demo skipped');
    },
  );

  test('progress is saved and resumes at the start of the topic', () async {
    await tutorial.maybeStart();
    tutorial.next();
    tutorial.emit('sheet-open:income');
    await Future<void>.delayed(Duration.zero);
    expect(await saved(), 'income-demo');

    tutorial.reset();
    await tutorial.maybeStart();
    expect(tutorial.step!.id, 'income-open');
  });

  test('finishing (or skipping) is final until restarted from Help', () async {
    await tutorial.maybeStart();
    await tutorial.finish();
    expect(tutorial.active, isFalse);
    expect(await saved(), TutorialController.doneValue);

    tutorial.reset();
    await tutorial.maybeStart();
    expect(tutorial.active, isFalse);

    await tutorial.restart();
    expect(tutorial.step!.id, 'balance');
    expect(await saved(), 'balance');
  });

  test('walking every step to the end marks the tutorial done', () async {
    await tutorial.maybeStart();
    var guard = 0;
    while (tutorial.active && guard++ < 50) {
      final step = tutorial.step!;
      if (step.until == null || tutorial.waitsForNext) {
        tutorial.next();
      } else {
        tutorial.emit(step.until!);
      }
    }
    expect(tutorial.active, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(await saved(), TutorialController.doneValue);
  });

  test('every step has a topic in range and Arabic text', () {
    final ids = tutorialSteps.map((step) => step.id).toSet();
    expect(ids, hasLength(tutorialSteps.length));
    expect(tutorialSteps.map((step) => step.topic).toSet(), {
      for (var i = 1; i <= tutorialTopicCount; i++) i,
    });
    for (final step in tutorialSteps) {
      expect(step.title, isNotEmpty);
      expect(step.body.length, greaterThan(20));
      // A step either points at a control or is a hint that waits for an
      // event (never a dead end).
      expect(
        step.target != null || step.until != null,
        isTrue,
        reason: step.id,
      );
    }
  });

  test('skip asks first, and can be cancelled', () async {
    await tutorial.maybeStart();
    tutorial.requestSkip();
    expect(tutorial.skipRequested, isTrue);
    tutorial.cancelSkip();
    expect(tutorial.skipRequested, isFalse);
    expect(tutorial.active, isTrue);
  });
}
