import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/services/home_widget_sync.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/system_notifications.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_motion.dart';
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
import 'package:waffr/widgets/brand/streak_celebration.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';

// Bottom navigation shell. Five tabs: home, report, savings, online, profile.
// Settings and notifications are pushed from the header, not tabs.
class AppShell extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final VoidCallback onThemeChanged;
  final dynamic appFlowController;

  const AppShell({
    super.key,
    required this.themeNotifier,
    required this.onThemeChanged,
    required this.appFlowController,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();

  // Target page while a tap-driven switch is in flight; pages the pager
  // passes on the way are not reported as the selected tab.
  int? _animatingToPage;

  // Pager opacity for the fade-through used on tabs that are not neighbors.
  late final AnimationController _pagerFade = AnimationController(
    vsync: this,
    value: 1,
  );

  Timer? _dueTimer;
  bool _syncingEvents = false;
  StreamSubscription<Uri?>? _widgetTaps;

  // Set when today's open extended the streak; drives the overlay once.
  StreakIncrease? _streakIncrease;

  static const int _tabCount = 5;

  // Lazy tab cache: _tabAt builds a page on first visit and reuses it.
  // Each tab uses AutomaticKeepAliveClientMixin so scroll position survives
  // after the first visit; unopened tabs are never built.
  final List<Widget?> _builtTabs = List<Widget?>.filled(_tabCount, null);

  // Creates the page for [index] once, then returns the cached widget.
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
    _builtTabs[index] = page;
    return page;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDueTimer();
    _syncFinancialEvents();
    unawaited(HomeWidgetSync.instance.start());
    _listenToWidgetTaps();
  }

  // A tap on a home screen widget opens the app on the matching place.
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
      ProfileIdentity.instance.reload();
    } else if (state == AppLifecycleState.paused) {
      _dueTimer?.cancel();
      _dueTimer = null;
    }
  }

  // Due periods, recurring expenses, streak, and notification evaluation.
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

  // Lets the home screen settle on screen before the overlay starts.
  Future<void> _showStreakIncrease(StreakIncrease? increase) async {
    if (increase == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _streakIncrease = increase);
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          themeNotifier: widget.themeNotifier,
          onThemeChanged: widget.onThemeChanged,
          appFlowController: widget.appFlowController,
        ),
      ),
    );
    if (!mounted) return;
    await ProfileIdentity.instance.reload();
  }

  // The bar highlight moves with the tap. Neighbor tabs slide; farther tabs
  // fade through, so the pager never sweeps past (and builds) the tabs
  // between them.
  void _onTabTapped(int index) {
    if (index == _tabIndex.value && _animatingToPage == null) return;
    if (_animatingToPage == index) return;

    final from = _pageController.hasClients
        ? (_pageController.page?.round() ?? _tabIndex.value)
        : _tabIndex.value;

    AppHaptics.selection();
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

  // Fades the pager out, jumps to [index], and fades back in.
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

  // Tap switch finished; the pager's resting page is the selected tab.
  void _settleTap(int index) {
    if (!mounted) return;
    if (_animatingToPage != index) return;
    _animatingToPage = null;
    final settled =
        _pageController.hasClients ? _pageController.page?.round() : null;
    if (settled != null && settled != _tabIndex.value) {
      _tabIndex.value = settled;
    }
  }

  // Swipe settled (or ignored while a conflicting tap animation is in flight).
  void _onPageChanged(int index) {
    if (_animatingToPage != null && index != _animatingToPage) {
      return;
    }
    _animatingToPage = null;
    if (index == _tabIndex.value) return;
    _tabIndex.value = index;
  }

  @override
  void dispose() {
    _dueTimer?.cancel();
    _widgetTaps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _pagerFade.dispose();
    _tabIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;

    final increase = _streakIncrease;

    return AppShellScope(
      selectTab: _onTabTapped,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Column(
                children: [
                  WaffrPageHeader(
                    applySafeArea: false,
                    leadingWidth: 96,
                    leading: Row(
                      children: [
                        IconButton(
                          iconSize: 30,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          icon: Icon(
                            Icons.settings_rounded,
                            color: isDark
                                ? AppColors.darkAccent
                                : AppColors.lightAccent,
                          ),
                          onPressed: _openSettings,
                        ),
                        _NotificationsButton(
                          accent: isDark
                              ? AppColors.darkAccent
                              : AppColors.lightAccent,
                          onPressed: _openNotifications,
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
                  Expanded(
                    // Only the visible page is built: zero viewport cache and no
                    // implicit neighbor scrolling. Pages come from _tabAt.
                    child: FadeTransition(
                      opacity: _pagerFade,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _tabCount,
                        allowImplicitScrolling: false,
                        scrollCacheExtent: const ScrollCacheExtent.viewport(0),
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) => _tabAt(index),
                      ),
                    ),
                  ),
                  _BottomNavBar(
                    tabIndex: _tabIndex,
                    tabCount: _tabCount,
                    onTap: _onTabTapped,
                  ),
                ],
              ),
            ),
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

// Icon row under the PageView; the selected icon grows and a pill slides
// under it.
class _BottomNavBar extends StatelessWidget {
  final ValueNotifier<int> tabIndex;
  final int tabCount;
  final ValueChanged<int> onTap;

  const _BottomNavBar({
    required this.tabIndex,
    required this.tabCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surface =
        isDark ? AppColors.darkSurface : AppColors.lightBackground;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, currentIndex, _) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / tabCount;
              const pillWidth = 18.0;

              return Stack(
                children: [
                  Row(
                    children: List.generate(tabCount, (index) {
                      final isSelected = index == currentIndex;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onTap(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: AnimatedScale(
                                scale: isSelected ? 1.25 : 1.0,
                                duration: AppMotion.of(context, AppMotion.medium),
                                curve: AppMotion.enter,
                                child: Icon(
                                  _icons[index],
                                  size: 26,
                                  color: isSelected
                                      ? accent
                                      : textPrimary.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  AnimatedPositionedDirectional(
                    duration: AppMotion.of(context, AppMotion.slow),
                    curve: AppMotion.enter,
                    start: slotWidth * currentIndex + (slotWidth - pillWidth) / 2,
                    bottom: 3,
                    width: pillWidth,
                    height: 3,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  static const List<IconData> _icons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.wallet_rounded,
    Icons.public_rounded,
    Icons.person_rounded,
  ];
}

// Header bell. Unread dot comes from NotificationService, not a tab.
class _NotificationsButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onPressed;

  const _NotificationsButton({
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService.instance,
      builder: (context, _) {
        final unread = NotificationService.instance.unreadCount;

        return IconButton(
          iconSize: 30,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: 48,
            height: 48,
          ),
          onPressed: onPressed,
          icon: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_rounded,
                  size: 30,
                  color: accent,
                ),
                if (unread > 0)
                  PositionedDirectional(
                    top: 0,
                    start: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
