// The signed-in app shell: header, lazily built tab pager, floating bottom
// navigation bar, and the background work that runs while the app is open
// (due periods, reminders, home-widget and notification taps).

import 'package:waffr/widgets/motion/origin_route.dart';
import 'package:waffr/core/theme/app_icons.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/services/home_widget_sync.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/system_notifications.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/screens/offline/home/dashboard.dart';
import 'package:waffr/screens/offline/home/sheets/add_expense_sheet.dart';
import 'package:waffr/screens/offline/home/sheets/add_income_sheet.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/savings/sheets/create_goal_sheet.dart';
import 'package:waffr/screens/offline/notifications/notifications_screen.dart';
import 'package:waffr/screens/offline/profile/profile_screen.dart';
import 'package:waffr/screens/online/online_screen.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/screens/offline/savings/savings_screen.dart';
import 'package:waffr/screens/offline/settings/settings_screen.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/brand/goal_celebration.dart';
import 'package:waffr/widgets/brand/streak_celebration.dart';
import 'package:waffr/widgets/brand/waffr_mood_logo.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/button/glass_button.dart';
import 'package:waffr/widgets/containers/floating_glass.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';
import 'package:waffr/widgets/glass/liquid_glass.dart';
import 'package:waffr/screens/offline/smart/smart_analysis_screen.dart';
import 'package:waffr/data/services/smart_settings.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/core/insights/smart/smart_facts_loader.dart';
import 'package:waffr/core/insights/smart/reminder_digest.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// Bottom navigation shell. Five tabs: home, report, savings, online, profile.
/// The tab bar floats over the pages; each tab keeps [kFloatingNavClearance]
/// free at the bottom of its scroll content.
/// Settings and notifications are pushed from the header, not tabs.
class AppShell extends StatefulWidget {
  /// Current theme mode, handed through to the settings screen.
  final ValueNotifier<ThemeMode> themeNotifier;

  /// Toggles light/dark; handed through to the settings screen.
  final VoidCallback onThemeChanged;

  /// The app's flow-controller state (from `main.dart`), handed to settings
  /// so it can sign out or refresh the app-lock gate.
  final dynamic appFlowController;

  /// Creates a [AppShell].
  const AppShell({
    super.key,
    required this.themeNotifier,
    required this.onThemeChanged,
    required this.appFlowController,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

/// State of [AppShell]. Owns the page controller, the selected-tab notifier,
/// the per-minute due-events timer, and the home-widget / notification tap
/// subscriptions.
class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Selected tab; the bar, the tab tickers and the profile page listen.
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();

  /// Target page while a tap-driven switch is in flight; pages the pager
  /// passes on the way are not reported as the selected tab.
  int? _animatingToPage;

  /// Pager opacity for the fade-through used on tabs that are not neighbors.
  late final AnimationController _pagerFade = AnimationController(
    vsync: this,
    value: 1,
  );

  /// Re-runs [_syncFinancialEvents] every minute while in the foreground.
  Timer? _dueTimer;

  /// Guards [_syncFinancialEvents] against overlapping runs.
  bool _syncingEvents = false;

  /// Home-screen widget taps.
  StreamSubscription<Uri?>? _widgetTaps;

  /// System notification taps.
  StreamSubscription<String>? _notificationTaps;

  /// Set when today's open extended the streak; drives the overlay once.
  StreakIncrease? _streakIncrease;

  /// Completed goals already known, so only a goal finished while the app
  /// is open is celebrated. Null until the store has loaded.
  Set<String>? _completedGoals;

  /// Name of the goal being celebrated, if one just completed.
  String? _goalReached;

  static const int _tabCount = 5;

  /// Lazy tab cache: [_tabAt] builds a page on first visit and reuses it.
  /// Each tab uses AutomaticKeepAliveClientMixin so scroll position survives
  /// after the first visit; unopened tabs are never built.
  final List<Widget?> _builtTabs = List<Widget?>.filled(_tabCount, null);

  /// Creates the page for [index] once, then returns the cached widget.
  Widget _tabAt(int index) {
    final existing = _builtTabs[index];
    if (existing != null) return existing;

    final Widget page = switch (index) {
      0 => const HomeScreen(),
      1 => const ReportScreen(),
      2 => const SavingsScreen(),
      3 => const OnlineScreen(),
      _ => ProfileScreen(tabIndex: _tabIndex),
    };
    // Keep tab state, but mute its tickers and store-driven builders when
    // another tab is selected. The child stays cached across switches.
    final tab = ValueListenableBuilder<int>(
      valueListenable: _tabIndex,
      child: page,
      builder: (context, selected, child) => TickerMode(
        enabled: selected == index,
        // Retained pages must not expose duplicate controls to screen readers
        // while the next tab's period selector is on screen.
        child: ExcludeSemantics(excluding: selected != index, child: child!),
      ),
    );
    _builtTabs[index] = tab;
    return tab;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TransactionStore.instance.addListener(_watchGoals);
    TransactionStore.instance.ensureLoaded().then((_) => _watchGoals());
    _startDueTimer();
    _syncFinancialEvents();
    unawaited(HomeWidgetSync.instance.start());
    _listenToWidgetTaps();
    _listenToNotificationTaps();
    unawaited(_syncComebackReminders());
  }

  /// Reminders that only fire if the app stays closed for days; every open
  /// pushes them forward. Each states a fact from the user's own numbers.
  Future<void> _syncComebackReminders() async {
    final settings = SmartSettings.instance;
    final notifications = NotificationService.instance;
    await Future.wait([settings.ensureLoaded(), notifications.ensureLoaded()]);
    final enabled = settings.alerts && !notifications.isMuted;
    (String, String)? soon;
    (String, String)? later;
    (String, String)? weekly;
    // Pick the first and second reminder from different kinds, plus the
    // weekly digest; all stay null when alerts are off.
    if (enabled) {
      final facts = await SmartFactsLoader.load();
      final digest = ReminderDigest(facts);
      final first = digest.candidates(SystemNotifications.soonAt(facts.now));
      final second = digest
          .candidates(SystemNotifications.laterAt(facts.now))
          .where((item) => first.isEmpty || item.kind != first.first.kind);
      if (first.isNotEmpty) soon = (first.first.title, first.first.body);
      if (second.isNotEmpty) later = (second.first.title, second.first.body);
      final week = digest.weekly();
      if (week != null) weekly = (week.title, week.body);
    }
    await SystemNotifications.instance.syncComebackReminders(
      enabled: enabled,
      soon: soon,
      later: later,
      weekly: weekly,
    );
  }

  /// Smart reminders open the analysis, both on cold launch and while open.
  void _listenToNotificationTaps() {
    final system = SystemNotifications.instance;
    system.launchPayload().then(_openFromNotification);
    _notificationTaps = system.taps.listen(_openFromNotification);
  }

  /// Opens the smart analysis on top of the shell for a smart-reminder tap.
  void _openFromNotification(String? payload) {
    if (payload != SystemNotifications.smartPayload) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      openSmartAnalysis(context, InsightScope.reports);
    });
  }

  /// A tap on a home screen widget opens the app on the matching place.
  void _listenToWidgetTaps() {
    if (!HomeWidgetSync.supported) return;
    HomeWidget.initiallyLaunchedFromHomeWidget()
        .then(_openFromWidget)
        .catchError((Object _) {});
    _widgetTaps = HomeWidget.widgetClicked.listen(
      _openFromWidget,
      onError: (Object _) {},
    );
  }

  /// Routes a widget deep link (by URI host) to a tab and/or sheet.
  void _openFromWidget(Uri? uri) {
    if (uri == null || uri.host.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      switch (uri.host) {
        case 'add-expense':
          _onTabTapped(0);
          showAddExpenseSheet(context);
        case 'add-income':
          _onTabTapped(0);
          showAddIncomeSheet(context);
        case 'savings':
          _onTabTapped(2);
        case 'create-goal':
          _onTabTapped(2);
          showCreateGoalSheet(context);
        case 'obligations':
          showObligationsSheet(context);
        case 'profile':
          _onTabTapped(4);
        default:
          _onTabTapped(0);
      }
    });
  }

  /// (Re)starts the one-minute [_dueTimer].
  void _startDueTimer() {
    _dueTimer?.cancel();
    _dueTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncFinancialEvents();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startDueTimer();
      _syncFinancialEvents();
      unawaited(_syncComebackReminders());
      ProfileIdentity.instance.reload();
    } else if (state == AppLifecycleState.paused) {
      _dueTimer?.cancel();
      _dueTimer = null;
    }
  }

  /// Due periods, recurring expenses, streak, and notification evaluation.
  Future<void> _syncFinancialEvents() async {
    if (_syncingEvents) return;
    _syncingEvents = true;
    try {
      final notifications = NotificationService.instance;
      await notifications.ensureLoaded();
      notifications.listen();
      await TransactionStore.instance.processDuePeriods();
      await RecurringExpenseStore.instance.ensureLoaded();
      await RecurringExpenseStore.instance.processDue();
      await CategoryStore.instance.ensureLoaded();
      await notifications.evaluate();
      final streak = await UsageStreakService.instance.recordToday();
      await SystemNotifications.instance.syncStreakReminder(
        enabled: !notifications.isMuted && streak.count >= 2,
        streakCount: streak.count,
      );
      _showStreakIncrease(UsageStreakService.instance.takeIncrease());
    } finally {
      _syncingEvents = false;
    }
  }

  /// Shows the streak overlay after a short delay so the home screen can
  /// settle on screen first.
  Future<void> _showStreakIncrease(StreakIncrease? increase) async {
    if (increase == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _streakIncrease = increase);
  }

  /// The header buttons; pages they open grow out of them.
  final GlobalKey _settingsButton = GlobalKey();
  final GlobalKey _bellButton = GlobalKey();

  void _openNotifications() {
    Navigator.of(context).push(
      originPageRoute<void>(
        _bellButton.currentContext ?? context,
        (_) => const NotificationsScreen(),
      ),
    );
  }

  /// Long press on the bell: mute or unmute without opening the list.
  Future<void> _toggleNotificationsMuted() async {
    final service = NotificationService.instance;
    await service.ensureLoaded();
    await service.toggleMuted();
    if (!mounted) return;
    AppHaptics.success();
    showAppSnackBar(
      context,
      service.isMuted ? 'تم كتم الإشعارات' : 'تم تفعيل الإشعارات',
      kind: AppFeedbackKind.info,
    );
  }

  /// Pushes settings, then reloads [ProfileIdentity] in case the account
  /// changed there.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      originPageRoute<void>(
        _settingsButton.currentContext ?? context,
        (_) => SettingsScreen(
          themeNotifier: widget.themeNotifier,
          onThemeChanged: widget.onThemeChanged,
          appFlowController: widget.appFlowController,
        ),
      ),
    );
    if (!mounted) return;
    await ProfileIdentity.instance.reload();
  }

  /// The bar highlight moves with the tap. Neighbor tabs slide; farther tabs
  /// fade through, so the pager never sweeps past (and builds) the tabs
  /// between them.
  void _onTabTapped(int index) {
    if (index == _tabIndex.value && _animatingToPage == null) return;
    if (_animatingToPage == index) return;

    final from = _pageController.hasClients
        ? (_pageController.page?.round() ?? _tabIndex.value)
        : _tabIndex.value;

    _tabIndex.value = index;
    if (!_pageController.hasClients) return;
    _animatingToPage = index;

    if ((index - from).abs() > 1 || AppMotion.reduced(context)) {
      _fadeThroughTo(index);
      return;
    }

    // A fade-through still running is cut short and the pager shown again.
    if (_pagerFade.value < 1) {
      _pagerFade.animateTo(1, duration: AppMotion.fast, curve: AppMotion.enter);
    }
    _pageController
        .animateToPage(
          index,
          duration: AppMotion.medium,
          curve: AppMotion.standard,
        )
        .whenComplete(() => _settleTap(index));
  }

  /// Fades the pager out, jumps to [index], and fades back in.
  Future<void> _fadeThroughTo(int index) async {
    final reduced = AppMotion.reduced(context);
    if (!reduced) {
      try {
        await _pagerFade
            .animateTo(0, duration: AppMotion.instant, curve: AppMotion.exit)
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || _animatingToPage != index) return;
    _pageController.jumpToPage(index);
    _settleTap(index);
    if (!reduced) {
      _pagerFade.animateTo(1, duration: AppMotion.fast, curve: AppMotion.enter);
    } else {
      _pagerFade.value = 1;
    }
  }

  /// Tap switch finished; the pager's resting page is the selected tab.
  void _settleTap(int index) {
    if (!mounted) return;
    if (_animatingToPage != index) return;
    _animatingToPage = null;
    final settled = _pageController.hasClients
        ? _pageController.page?.round()
        : null;
    if (settled != null && settled != _tabIndex.value) {
      _tabIndex.value = settled;
    }
  }

  /// Swipe settled (or ignored while a conflicting tap animation is in
  /// flight).
  void _onPageChanged(int index) {
    if (_animatingToPage != null && index != _animatingToPage) {
      return;
    }
    _animatingToPage = null;
    if (index == _tabIndex.value) return;
    _tabIndex.value = index;
  }

  /// Celebrates a goal that was completed since the last look. The first
  /// look only records what is already complete.
  void _watchGoals() {
    final store = TransactionStore.instance;
    if (!mounted || !store.isLoaded) return;
    final done = {for (final goal in store.allCompletedGoals) goal.id: goal};
    final known = _completedGoals;
    _completedGoals = done.keys.toSet();
    if (known == null) return;
    for (final id in done.keys) {
      if (known.contains(id)) continue;
      setState(() => _goalReached = done[id]!.name);
      return;
    }
  }

  @override
  void dispose() {
    TransactionStore.instance.removeListener(_watchGoals);
    _dueTimer?.cancel();
    _widgetTaps?.cancel();
    _notificationTaps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _pagerFade.dispose();
    _tabIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final bg = palette.background;

    final increase = _streakIncrease;

    return AppShellScope(
      selectTab: _onTabTapped,
      child: Scaffold(
        backgroundColor: bg,
        // No tab has a text field; sheets handle the keyboard themselves.
        // Resizing here would re-lay out the visible tab on every keyboard
        // frame behind an open sheet.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The light field every tab sits on; the glass chrome bends it.
            const Positioned.fill(child: AuroraBackdrop()),
            // Tab pager. It starts below the header, but its pages paint
            // past that edge, so content scrolls up beneath the glass.
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  top:
                      MediaQuery.paddingOf(context).top +
                      WaffrPageHeader.height,
                ),
                // Only the visible page is built: zero viewport cache and no
                // implicit neighbor scrolling. Pages come from _tabAt.
                child: AnimatedBuilder(
                  animation: _pagerFade,
                  // The lens needs a settled page; blur stays while fading.
                  builder: (context, child) => LiquidGlassScope(
                    refract: _pagerFade.value >= 1,
                    child: child!,
                  ),
                  child: FadeTransition(
                    opacity: _pagerFade,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _tabCount,
                      clipBehavior: Clip.none,
                      allowImplicitScrolling: false,
                      scrollCacheExtent: const ScrollCacheExtent.viewport(0),
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => _tabAt(index),
                    ),
                  ),
                ),
              ),
            ),
            // Glass header (settings, bell, mood logo, wordmark) over the
            // pager.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: WaffrPageHeader(
                leadingWidth: 104,
                // The logo, smiling with the wallet's current mood.
                center: const WaffrMoodLogo(size: 46),
                leading: Row(
                  children: [
                    GlassIconButton(
                      key: _settingsButton,
                      icon: AppIcons.settings,
                      label: 'الإعدادات',
                      onPressed: _openSettings,
                    ),
                    const SizedBox(width: 8),
                    _NotificationsButton(
                      key: _bellButton,
                      onPressed: _openNotifications,
                      onLongPress: _toggleNotificationsMuted,
                    ),
                  ],
                ),
                title: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'WAFFR',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontFamily: 'BebasNeue',
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
            // Floats over the pages so content scrolls under its glass.
            // Hidden while the keyboard is up so it never covers a field.
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 10,
              child: _HideOnKeyboard(
                child: RepaintBoundary(
                  child: _BottomNavBar(
                    tabIndex: _tabIndex,
                    tabCount: _tabCount,
                    pageController: _pageController,
                    onTap: _onTabTapped,
                  ),
                ),
              ),
            ),
            // One-shot goal celebration over everything.
            if (_goalReached case final name?)
              Positioned.fill(
                child: GoalCelebrationOverlay(
                  key: ValueKey('goal-$name'),
                  goalName: name,
                  onFinished: () {
                    if (mounted) setState(() => _goalReached = null);
                  },
                ),
              ),
            // One-shot streak celebration over everything.
            if (increase != null)
              Positioned.fill(
                child: StreakCelebrationOverlay(
                  key: ValueKey('streak-${increase.to}'),
                  from: increase.from,
                  to: increase.to,
                  onFinished: () {
                    if (mounted) setState(() => _streakIncrease = null);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Slides the nav bar away while the keyboard is up so it never covers a
/// field. Only this small widget depends on the keyboard inset, so the
/// shell itself does not rebuild on every keyboard frame.
class _HideOnKeyboard extends StatelessWidget {
  final Widget child;

  const _HideOnKeyboard({required this.child});

  @override
  Widget build(BuildContext context) {
    final hidden = MediaQuery.viewInsetsOf(context).bottom > 0;
    final duration = AppMotion.of(context, AppMotion.fast);
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedSlide(
        offset: hidden ? const Offset(0, 1.6) : Offset.zero,
        duration: duration,
        curve: hidden ? AppMotion.exit : AppMotion.enter,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: duration,
          child: child,
        ),
      ),
    );
  }
}

/// Floating liquid-glass tab bar over the pages. The highlight follows the
/// pager position, stretching while it moves between tabs, and the selected
/// tab opens to show its name beside the icon.
class _BottomNavBar extends StatelessWidget {
  final ValueNotifier<int> tabIndex;
  final int tabCount;
  final PageController pageController;
  final ValueChanged<int> onTap;

  const _BottomNavBar({
    required this.tabIndex,
    required this.tabCount,
    required this.pageController,
    required this.onTap,
  });

  /// Tab icons, in page order.
  static const List<IconData> _icons = [
    AppIcons.home,
    AppIcons.reports,
    AppIcons.savings,
    AppIcons.online,
    AppIcons.profile,
  ];

  /// Screen-reader labels, in page order.
  static const List<String> _labels = [
    'الرئيسية',
    'التقارير',
    'التوفير',
    'الإنترنت',
    'الملف الشخصي',
  ];

  /// Short names shown inside the highlight of the selected tab.
  static const List<String> _titles = [
    'الرئيسية',
    'التقارير',
    'التوفير',
    'الإنترنت',
    'حسابي',
  ];

  static const double _height = 64;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(32));

  /// How much wider than its neighbors the selected slot grows, as a
  /// multiple of a plain slot.
  static const double _grow = 1.5;

  static const TextStyle _titleStyle = TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: ['Tajawal'],
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  /// 1 on the tab the pager rests on, 0 one tab away.
  static double _nearness(double page, int index) =>
      (1 - (page - index).abs()).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textPrimary = palette.textPrimary;
    final accent = palette.accent;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return FloatingGlass(
      radius: _radius,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const inset = 6.0;
            final track = constraints.maxWidth - inset * 2;
            return AnimatedBuilder(
              animation: Listenable.merge([pageController, tabIndex]),
              builder: (context, _) {
                final page =
                    pageController.hasClients &&
                        pageController.position.haveDimensions
                    ? (pageController.page ?? tabIndex.value.toDouble())
                    : tabIndex.value.toDouble();

                // The selected slot is wider to hold its name; widths
                // follow the pager, so two neighbors share the room while
                // it moves between them.
                final weights = [
                  for (var i = 0; i < tabCount; i++)
                    1 + _grow * _nearness(page, i),
                ];
                final unit = track / weights.fold<double>(0, (a, b) => a + b);
                final widths = [for (final w in weights) w * unit];
                final starts = <double>[];
                var x = inset;
                for (final w in widths) {
                  starts.add(x);
                  x += w;
                }

                return Stack(
                  children: [
                    _indicator(page, starts, widths, constraints.maxWidth, rtl),
                    for (var i = 0; i < tabCount; i++)
                      Positioned(
                        left: rtl
                            ? constraints.maxWidth - starts[i] - widths[i]
                            : starts[i],
                        top: 0,
                        bottom: 0,
                        width: widths[i],
                        child: _tab(context, i, page, accent, textPrimary),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Highlight bubble for the fractional pager [page]: it blends the two
  /// slots it is between and stretches a little while it travels.
  Widget _indicator(
    double page,
    List<double> starts,
    List<double> widths,
    double total,
    bool rtl,
  ) {
    final from = page.floor().clamp(0, tabCount - 1);
    final to = page.ceil().clamp(0, tabCount - 1);
    final frac = page - page.floorToDouble();
    final stretch = math.sin(frac * math.pi);
    double mix(double a, double b) => a + (b - a) * frac;

    final centerLtr = mix(
      starts[from] + widths[from] / 2,
      starts[to] + widths[to] / 2,
    );
    final width = mix(widths[from], widths[to]) * (1 + 0.12 * stretch) - 4;
    final height = 48 - 6 * stretch;
    final center = rtl ? total - centerLtr : centerLtr;

    return Positioned(
      left: center - width / 2,
      top: (_height - height) / 2,
      width: width,
      height: height,
      child: FloatingGlassHighlight(radius: height / 2),
    );
  }

  /// One tap target. The icon tints toward [accent] as the highlight
  /// approaches, and the tab's name opens beside it.
  Widget _tab(
    BuildContext context,
    int index,
    double page,
    Color accent,
    Color textPrimary,
  ) {
    final t = _nearness(page, index);
    final eased = AppMotion.soft.transform(t);
    final color = Color.lerp(textPrimary.withValues(alpha: 0.45), accent, t)!;
    return Semantics(
      button: true,
      label: _labels[index],
      selected: index == tabIndex.value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(index);
        },
        child: ExcludeSemantics(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 1 + 0.08 * eased,
                  child: Icon(_icons[index], size: 24, color: color),
                ),
                // The name takes its room only as the tab is selected.
                ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: eased,
                    child: Opacity(
                      opacity: (t * 1.6 - 0.6).clamp(0.0, 1.0),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 7),
                        child: Text(
                          _titles[index],
                          maxLines: 1,
                          softWrap: false,
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.15),
                          style: _titleStyle.copyWith(color: accent),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header bell. Unread dot and muted state come from NotificationService.
/// A long press mutes or unmutes.
class _NotificationsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  const _NotificationsButton({
    super.key,
    required this.onPressed,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService.instance,
      builder: (context, _) {
        final service = NotificationService.instance;
        final muted = service.isMuted;
        return GlassIconButton(
          icon: muted ? AppIcons.bellOff : AppIcons.bell,
          label: muted
              ? 'الإشعارات مكتومة. اضغط مطولاً لتفعيلها'
              : 'الإشعارات. اضغط مطولاً للكتم',
          onPressed: onPressed,
          onLongPress: onLongPress,
          dimmed: muted,
          showDot: service.unreadCount > 0,
        );
      },
    );
  }
}
