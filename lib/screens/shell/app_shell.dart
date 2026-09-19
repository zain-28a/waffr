import 'package:flutter/material.dart';
import 'package:waffer/core/data/category_store.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/screens/offline/home/dashboard.dart';
import 'package:waffer/screens/offline/notifications/notifications_screen.dart';
import 'package:waffer/screens/offline/placeholder/placeholder.dart';
import 'package:waffer/screens/offline/report/reportscreen.dart';
import 'package:waffer/screens/offline/savings/savings_screen.dart';
import 'package:waffer/screens/offline/settings/settings_screen.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

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

  /// Tap target while the page animation is in flight; selection waits for it.
  int? _animatingToPage;

  static const int _tabCount = 5;

  static const List<Widget> _tabPages = [
    HomeScreen(),
    ReportScreen(),
    SavingsScreen(),
    PlaceholderScreen(label: 'شاشة 4'),
    NotificationsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncFinancialEvents();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncFinancialEvents();
    }
  }

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
                  'Waffer',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _tabCount,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _tabPages[index],
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
                                            : Icons.circle_outlined,
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
