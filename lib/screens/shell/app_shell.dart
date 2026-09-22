import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:waffer/data/stores/category_store.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/data/stores/recurring_expense_store.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/screens/offline/home/dashboard.dart';
import 'package:waffer/screens/offline/notifications/notifications_screen.dart';
import 'package:waffer/screens/online/online_screen.dart';
import 'package:waffer/screens/offline/report/reportscreen.dart';
import 'package:waffer/screens/offline/savings/savings_screen.dart';
import 'package:waffer/screens/offline/settings/settings_screen.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

// Bottom navigation shell. Five tabs: home, report, savings, online,
// notifications. Settings is a pushed route from the header, not a tab.
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
      _ => const NotificationsScreen(),
    };
    _builtTabs[index] = page;
    return page;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncFinancialEvents();
    _dueTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncFinancialEvents();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncFinancialEvents();
    }
  }

  // Due periods, recurring expenses, and notification evaluation.
  Future<void> _syncFinancialEvents() async {
    final notifications = NotificationService.instance;
    await notifications.ensureLoaded();
    notifications.listen();
    await TransactionStore.instance.processDuePeriods();
    await RecurringExpenseStore.instance.ensureLoaded();
    await RecurringExpenseStore.instance.processDue();
    await CategoryStore.instance.ensureLoaded();
    await notifications.evaluate();
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

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            WafferPageHeader(
              applySafeArea: false,
              leading: Padding(
                padding: const EdgeInsets.only(top: 15),
                child: IconButton(
                  iconSize: 30,
                  icon: Icon(
                    Icons.settings_rounded,
                    color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          themeNotifier: widget.themeNotifier,
                          onThemeChanged: widget.onThemeChanged,
                          appFlowController: widget.appFlowController,
                        ),
                      ),
                    );
                  },
                ),
              ),
              title: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'waffr',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
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
            _BottomNavBar(
              tabIndex: _tabIndex,
              tabCount: _tabCount,
              onTap: _onTabTapped,
            ),
          ],
        ),
      ),
    );
  }
}

// Icon row under the PageView; selected item grows via AnimatedScale.
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
          child: Row(
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
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: index == 4
                            ? _NotificationsTabIcon(
                                selected: isSelected,
                                accent: accent,
                                idle: textPrimary.withValues(alpha: 0.35),
                              )
                            : Icon(
                                index == 0
                                    ? Icons.home_rounded
                                    : index == 1
                                        ? Icons.bar_chart_rounded
                                        : index == 2
                                            ? Icons.wallet_rounded
                                            : Icons.public_rounded,
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
        );
      },
    );
  }
}

// Bell with an unread dot driven by NotificationService.unreadCount.
class _NotificationsTabIcon extends StatelessWidget {
  final bool selected;
  final Color accent;
  final Color idle;

  const _NotificationsTabIcon({
    required this.selected,
    required this.accent,
    required this.idle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService.instance,
      builder: (context, _) {
        final unread = NotificationService.instance.unreadCount;

        return SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                selected
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                size: 26,
                color: selected ? accent : idle,
              ),
              if (unread > 0)
                PositionedDirectional(
                  top: 1,
                  start: 1,
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
        );
      },
    );
  }
}
