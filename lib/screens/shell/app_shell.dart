import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/system_notifications.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/screens/offline/home/dashboard.dart';
import 'package:waffr/screens/offline/notifications/notifications_screen.dart';
import 'package:waffr/screens/offline/profile/profile_screen.dart';
import 'package:waffr/screens/online/online_screen.dart';
import 'package:waffr/screens/offline/report/reportscreen.dart';
import 'package:waffr/screens/offline/savings/savings_screen.dart';
import 'package:waffr/screens/offline/settings/settings_screen.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/widgets/brand/streak_celebration.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/glass.dart';

// Bottom navigation shell. Five tabs: home, report, savings, online, profile.
// The tab bar floats over the pages; each tab keeps kFloatingNavClearance
// free at the bottom of its scroll content.
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();

  // Target page while animateToPage is in flight; stops the bar highlight
  // from flickering mid-animation.
  int? _animatingToPage;

  Timer? _dueTimer;
  bool _syncingEvents = false;

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

  // Animates the pager; highlight updates wait until the animation settles.
  void _onTabTapped(int index) {
    if (index == _tabIndex.value && _animatingToPage == null) return;
    if (_animatingToPage == index) return;

    _animatingToPage = index;
    _pageController
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .whenComplete(() {
          if (!mounted) return;
          if (_animatingToPage != index) return;
          _animatingToPage = null;
          final settled = _pageController.hasClients
              ? _pageController.page?.round()
              : null;
          if (settled != null && settled != _tabIndex.value) {
            _tabIndex.value = settled;
          }
        });
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
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
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
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _tabCount,
                      allowImplicitScrolling: false,
                      scrollCacheExtent: const ScrollCacheExtent.viewport(0),
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => _tabAt(index),
                    ),
                  ),
                ],
              ),
            ),
            // Floats over the pages so content scrolls under its blur.
            // Hidden while the keyboard is up so it never covers a field.
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 10,
              child: _BottomNavBar(
                tabIndex: _tabIndex,
                tabCount: _tabCount,
                pageController: _pageController,
                onTap: _onTabTapped,
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

// Floating "liquid glass" tab bar: a blurred, translucent pill over the
// pages. The highlight follows the pager position, stretching while it moves
// between tabs and settling round under the selected icon.
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

  static const List<IconData> _icons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.wallet_rounded,
    Icons.public_rounded,
    Icons.person_rounded,
  ];

  static const double _height = 64;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(32));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: CustomPaint(
            foregroundPainter: LiquidGlassPainter(
              radius: _radius,
              isDark: isDark,
            ),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                gradient: liquidGlassFill(
                  surface.withValues(alpha: isDark ? 0.62 : 0.6),
                  isDark: isDark,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / tabCount;
                  return AnimatedBuilder(
                    animation: Listenable.merge([pageController, tabIndex]),
                    builder: (context, _) {
                      final page = pageController.hasClients &&
                              pageController.position.haveDimensions
                          ? (pageController.page ?? tabIndex.value.toDouble())
                          : tabIndex.value.toDouble();
                      return Stack(
                        children: [
                          _indicator(page, slot, rtl, accent),
                          Row(
                            children: [
                              for (var i = 0; i < tabCount; i++)
                                Expanded(
                                  child: _tab(i, page, accent, textPrimary),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicator(double page, double slot, bool rtl, Color accent) {
    final frac = page - page.floorToDouble();
    final stretch = math.sin(frac * math.pi);
    final width = slot * 0.66 * (1 + 0.55 * stretch);
    final height = 44 - 6 * stretch;
    final center = (rtl ? tabCount - 1 - page : page) * slot + slot / 2;

    return Positioned(
      left: center - width / 2,
      top: (_height - height) / 2,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.24),
              accent.withValues(alpha: 0.14),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
      ),
    );
  }

  Widget _tab(int index, double page, Color accent, Color textPrimary) {
    // 1 under the highlight, 0 one tab away.
    final t = (1 - (page - index).abs()).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      selected: index == tabIndex.value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(index);
        },
        child: Center(
          child: Transform.scale(
            scale: 1 + 0.18 * Curves.easeOut.transform(t),
            child: Icon(
              _icons[index],
              size: 25,
              color: Color.lerp(
                textPrimary.withValues(alpha: 0.38),
                accent,
                t,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
