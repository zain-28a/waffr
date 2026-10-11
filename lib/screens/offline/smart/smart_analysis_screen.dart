// Smart analysis: "thinks" for a moment, then writes its findings out as
// if typing them, over a soft moving glow. Cards expand to show the
// numbers behind each finding and offer the matching action.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:waffr/core/insights/smart/insight_engine.dart';
import 'package:waffr/core/insights/smart/smart_facts_loader.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffr/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/manual_save_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/shopping_list_sheet.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/smart/smart_glow.dart';

String smartSparkHeroTag(InsightScope scope) => 'smart-spark-${scope.name}';

// Opens the analysis with a fade and gentle zoom from the button.
Future<void> openSmartAnalysis(BuildContext context, InsightScope scope) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: AppMotion.of(context, AppMotion.emphasized),
      reverseTransitionDuration: AppMotion.of(context, AppMotion.medium),
      pageBuilder: (_, _, _) => SmartAnalysisScreen(scope: scope),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.enter,
          reverseCurve: AppMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

enum _Phase { thinking, writing, done }

class SmartAnalysisScreen extends StatefulWidget {
  final InsightScope scope;

  const SmartAnalysisScreen({super.key, required this.scope});

  @override
  State<SmartAnalysisScreen> createState() => _SmartAnalysisScreenState();
}

class _SmartAnalysisScreenState extends State<SmartAnalysisScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _thinkingLines = [
    'أراجع مصاريفك…',
    'أقارن مع الفترات السابقة…',
    'أبحث عن الأنماط…',
    'أحسب التوقعات…',
    'أجهّز الاقتراحات…',
  ];

  late InsightScope _scope = widget.scope;
  final math.Random _seeds = math.Random();
  _Phase _phase = _Phase.thinking;
  SmartReport? _report;
  int _thinkingLine = 0;

  // Characters written so far across the headline, summary and card
  // bodies, read as one stream.
  int _revealed = 0;
  int _total = 0;

  // Writing speed follows elapsed time, not frames, so a slow device
  // writes in the same ~3 seconds with bigger steps.
  late final Ticker _typing = createTicker(_onTypingTick);
  double _charsPerMs = 0.15;

  Timer? _thinkingTicker;
  int _run = 0;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    // Reads MediaQuery (reduced motion), so it waits for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generate();
    });
  }

  @override
  void dispose() {
    _typing.dispose();
    _thinkingTicker?.cancel();
    super.dispose();
  }

  // Thinks, builds a fresh report with a new seed, then types it out.
  Future<void> _generate({bool quick = false}) async {
    final run = ++_run;
    _typing.stop();
    _thinkingTicker?.cancel();
    setState(() {
      _phase = _Phase.thinking;
      _expanded.clear();
      _thinkingLine = _seeds.nextInt(_thinkingLines.length);
    });

    final reduced = AppMotion.reduced(context);
    _thinkingTicker = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted) {
        setState(() => _thinkingLine = (_thinkingLine + 1) % _thinkingLines.length);
      }
    });

    final facts = await SmartFactsLoader.load();
    final report = InsightEngine(facts, seed: _seeds.nextInt(1 << 30))
        .analyze(_scope);
    final pause = reduced
        ? Duration.zero
        : Duration(milliseconds: quick ? 700 : 1500);
    await Future<void>.delayed(pause);
    if (!mounted || run != _run) return;
    _thinkingTicker?.cancel();

    final total = report.headline.length +
        report.summary.length +
        report.insights
            .where((item) => item.id != 'health-score')
            .fold<int>(0, (sum, item) => sum + item.body.length);
    setState(() {
      _report = report;
      _total = total;
      // Keep the whole write-out to roughly three seconds.
      _charsPerMs = math.max(0.12, total / 3000);
      _revealed = reduced ? total : 0;
      _phase = reduced ? _Phase.done : _Phase.writing;
    });
    if (reduced) {
      AppHaptics.success();
      return;
    }
    _lastTypingBuild = Duration.zero;
    _typing.start();
  }

  // Last tick that rebuilt the screen. Text is revealed about 30 times a
  // second instead of on every frame, which halves the rebuild and text
  // layout work while it still reads as smooth typing.
  Duration _lastTypingBuild = Duration.zero;

  void _onTypingTick(Duration elapsed) {
    final next = math.min(_total, (elapsed.inMilliseconds * _charsPerMs).round());
    if (next >= _total) {
      _finish();
      return;
    }
    if (next == _revealed) return;
    if (elapsed - _lastTypingBuild < const Duration(milliseconds: 33)) return;
    _lastTypingBuild = elapsed;
    setState(() => _revealed = next);
  }

  void _finish() {
    _typing.stop();
    if (_phase == _Phase.done) return;
    setState(() {
      _revealed = _total;
      _phase = _Phase.done;
    });
    AppHaptics.success();
  }

  void _selectScope(String label) {
    final next = InsightScope.values.firstWhere((scope) => scope.label == label);
    if (next == _scope) return;
    AppHaptics.selection();
    _scope = next;
    _generate(quick: true);
  }

  Future<void> _runAction(InsightAction action) async {
    AppHaptics.selection();
    // Rerun the analysis afterwards only if the action changed any data;
    // closing a sheet without saving should not replay the whole reading.
    var changed = false;
    void markChanged() => changed = true;
    final stores = Listenable.merge([
      TransactionStore.instance,
      RecurringExpenseStore.instance,
      ShoppingListStore.instance,
    ])
      ..addListener(markChanged);
    switch (action) {
      case InsightAction.addExpense:
        await showAddExpenseSheet(context);
      case InsightAction.addIncome:
        await showAddIncomeSheet(context);
      case InsightAction.createGoal:
        await showCreateGoalSheet(context);
      case InsightAction.manualSave:
        await showManualSaveSheet(context);
      case InsightAction.obligations:
        await showObligationsSheet(context);
      case InsightAction.shoppingList:
        await showShoppingListSheet(context);
      case InsightAction.expenseHistory:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const TransactionHistoryScreen.expenses(),
          ),
        );
    }
    stores.removeListener(markChanged);
    if (!changed || !mounted) return;
    // The data may have changed; refresh the reading quietly.
    if (mounted) _generate(quick: true);
  }

  // Visible part of a segment that starts at [offset] in the stream.
  String _slice(String text, int offset) {
    final count = (_revealed - offset).clamp(0, text.length);
    return text.substring(0, count);
  }

  bool _typingAt(String text, int offset) =>
      _phase == _Phase.writing &&
      _revealed > offset &&
      _revealed < offset + text.length;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final generating = _phase != _Phase.done;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: SmartGlowBackground(intensity: generating ? 1 : 0.4),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                WaffrBackHeader(
                  title: 'التحليل الذكي',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                  child: SheetChoiceChips(
                    options: [for (final scope in InsightScope.values) scope.label],
                    selected: _scope.label,
                    onSelected: _selectScope,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: _headlineRow(palette),
                ),
                Expanded(
                  child: GestureDetector(
                    // Tap while writing to show everything at once.
                    behavior: HitTestBehavior.translucent,
                    onTap: _phase == _Phase.writing ? _finish : null,
                    child: AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.slow),
                      switchInCurve: AppMotion.enter,
                      switchOutCurve: AppMotion.exit,
                      child: _phase == _Phase.thinking || _report == null
                          ? const _ThinkingView(key: ValueKey('thinking'))
                          : _reportView(_report!, palette),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The spark stays in one place across thinking and writing, so the hero
  // from the button lands on it and there is never a second copy.
  Widget _headlineRow(AppPalette palette) {
    final report = _report;
    final thinking = _phase == _Phase.thinking || report == null;
    final style = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: thinking ? 16 : 20,
      height: 1.4,
      fontWeight: thinking ? FontWeight.w700 : FontWeight.w800,
      color: palette.textPrimary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Hero(
          tag: smartSparkHeroTag(widget.scope),
          child: SmartSpark(size: 30, spinning: _phase != _Phase.done),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.topStart,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: thinking
                  ? Text(
                      _thinkingLines[_thinkingLine],
                      key: ValueKey('think-$_thinkingLine'),
                      style: style,
                    )
                  : _TypedText(
                      key: ValueKey('headline-$_run'),
                      text: _slice(report.headline, 0),
                      typing: _typingAt(report.headline, 0),
                      style: style,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportView(SmartReport report, AppPalette palette) {
    var offset = report.headline.length;
    final summaryAt = offset;
    offset += report.summary.length;
    // The gauge shows the health score and its breakdown, so its card is
    // not repeated in the list.
    final health = report.insights
        .where((item) => item.id == 'health-score')
        .firstOrNull;
    final insights = [
      for (final item in report.insights)
        if (item.id != 'health-score') item,
    ];
    final bodyOffsets = <int>[];
    for (final item in insights) {
      bodyOffsets.add(offset);
      offset += item.body.length;
    }

    return ListView(
      key: ValueKey('report-$_run'),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      children: [
        if (report.healthScore != null && _revealed > summaryAt) ...[
          const SizedBox(height: 8),
          Reveal(
            child: _HealthGauge(
              score: report.healthScore!,
              title: health?.title ?? 'مؤشر الصحة المالية',
              detail: health?.detail,
              expanded: _expanded.contains('health-score'),
              onToggle: () {
                AppHaptics.selection();
                setState(() {
                  if (!_expanded.remove('health-score')) {
                    _expanded.add('health-score');
                  }
                });
              },
            ),
          ),
        ],
        if (report.summary.isNotEmpty && _revealed > summaryAt) ...[
          const SizedBox(height: 10),
          _TypedText(
            text: _slice(report.summary, summaryAt),
            typing: _typingAt(report.summary, summaryAt),
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontSize: 14,
              height: 1.6,
              color: palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (var i = 0; i < insights.length; i++)
          if (_revealed >= bodyOffsets[i] &&
              (_revealed > bodyOffsets[i] || insights[i].body.isEmpty || _phase == _Phase.done))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reveal(
                key: ValueKey('${_run}_${insights[i].id}'),
                child: _InsightCard(
                  insight: insights[i],
                  body: _slice(insights[i].body, bodyOffsets[i]),
                  typing: _typingAt(insights[i].body, bodyOffsets[i]),
                  expanded: _expanded.contains(insights[i].id),
                  interactive: _phase == _Phase.done,
                  onToggle: () {
                    AppHaptics.selection();
                    setState(() {
                      final id = insights[i].id;
                      if (!_expanded.remove(id)) _expanded.add(id);
                    });
                  },
                  onAction: _runAction,
                ),
              ),
            ),
      ],
    );
  }
}

class _ThinkingView extends StatelessWidget {
  const _ThinkingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
      children: [
        const _Shimmer(widths: [1, 0.86, 0.62]),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++) ...[
          GlassContainer(
            colorType: GlassColorType.surface,
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: _Shimmer(widths: [0.5, 1, 0.78 - i * 0.12]),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// Placeholder lines with a moving highlight, in the glow colors.
class _Shimmer extends StatefulWidget {
  final List<double> widths;

  const _Shimmer({required this.widths});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.reduced(context) && !_sweep.isAnimating) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colors = smartGlowColors(context);
    final base = palette.textPrimary.withValues(alpha: 0.07);
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        final shift = _sweep.value * 3 - 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final width in widget.widths)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: width,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment(shift - 1, 0),
                        end: Alignment(shift + 1, 0),
                        colors: [
                          base,
                          colors[2].withValues(alpha: 0.28),
                          colors[0].withValues(alpha: 0.22),
                          base,
                        ],
                        stops: const [0.0, 0.4, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Text that is still being written, with a glowing caret at its end.
class _TypedText extends StatelessWidget {
  final String text;
  final bool typing;
  final TextStyle style;

  const _TypedText({
    super.key,
    required this.text,
    required this.typing,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text),
          if (typing)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _Caret(),
            ),
        ],
      ),
    );
  }
}

class _Caret extends StatelessWidget {
  const _Caret();

  @override
  Widget build(BuildContext context) {
    final colors = smartGlowColors(context);
    return Container(
      width: 9,
      height: 9,
      margin: const EdgeInsetsDirectional.only(start: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [colors[0], colors[2]]),
        boxShadow: [
          BoxShadow(color: colors[2].withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final SmartInsight insight;
  final String body;
  final bool typing;
  final bool expanded;
  final bool interactive;
  final VoidCallback onToggle;
  final ValueChanged<InsightAction> onAction;

  const _InsightCard({
    required this.insight,
    required this.body,
    required this.typing,
    required this.expanded,
    required this.interactive,
    required this.onToggle,
    required this.onAction,
  });

  Color _toneColor(BuildContext context, AppPalette palette) =>
      switch (insight.tone) {
        InsightTone.warning => AppColors.warningOf(context),
        InsightTone.positive => palette.accent,
        InsightTone.tip => const Color(0xFF3FA7C9),
        InsightTone.info => const Color(0xFF6E93C9),
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = _toneColor(context, palette);
    final hasMore = insight.detail != null || insight.action != null;

    return GestureDetector(
      onTap: interactive && hasMore ? onToggle : null,
      child: GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        // While the text is being typed the card simply grows with it; an
        // animated resize lagged behind each new line and made the cards
        // below move in steps. It animates only for expand/collapse.
        child: AnimatedSize(
          duration: typing
              ? Duration.zero
              : AppMotion.of(context, AppMotion.medium),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(insight.icon, size: 20, color: tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: const ['Tajawal'],
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _TypedText(
                          text: body,
                          typing: typing,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: const ['Tajawal'],
                            fontSize: 13.5,
                            height: 1.55,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasMore && interactive)
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.medium),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
              if (expanded) ...[
                if (insight.detail != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      insight.detail!,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: 12.5,
                        height: 1.7,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
                if (insight.action != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => onAction(insight.action!),
                      style: TextButton.styleFrom(
                        foregroundColor: tone,
                        backgroundColor: tone.withValues(alpha: 0.12),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(
                        insight.action!.label,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: ['Tajawal'],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Ring gauge for the 0-100 health score, counting up as it appears.
// Tapping it shows how each part contributed.
class _HealthGauge extends StatelessWidget {
  final int score;
  final String title;
  final String? detail;
  final bool expanded;
  final VoidCallback onToggle;

  const _HealthGauge({
    required this.score,
    required this.title,
    required this.detail,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colors = smartGlowColors(context);
    return GestureDetector(
      onTap: detail == null ? null : onToggle,
      child: GlassContainer(
        colorType: GlassColorType.surface,
        borderRadius: 22,
        padding: const EdgeInsets.all(16),
        child: AnimatedSize(
          duration: AppMotion.of(context, AppMotion.medium),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 74,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: score / 100),
                      duration: AppMotion.of(
                        context,
                        const Duration(milliseconds: 1100),
                      ),
                      curve: AppMotion.enter,
                      builder: (context, value, _) {
                        return CustomPaint(
                          painter: _GaugePainter(
                            value: value,
                            track: palette.textPrimary.withValues(alpha: 0.08),
                            colors: colors,
                          ),
                          child: Center(
                            child: Text(
                              '${(value * 100).round()}',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: const ['Tajawal'],
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'من 100، يجمع التوفير وكفاية الرصيد واتجاه الصرف والالتزامات وانتظام التسجيل.',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontFamilyFallback: const ['Tajawal'],
                            fontSize: 12,
                            height: 1.5,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (detail != null)
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.medium),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
              if (expanded && detail != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors[2].withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    detail!,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 12.5,
                      height: 1.7,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color track;
  final List<Color> colors;

  _GaugePainter({required this.value, required this.track, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [colors[0], colors[1], colors[2], colors[3]],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
