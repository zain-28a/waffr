
import 'package:flutter/material.dart';
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
import 'package:google_fonts/google_fonts.dart';
import 'package:waffer/widgets/brand/waffer_w_mark.dart';


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
  final PageController _pageController =
      PageController(initialPage: 0);

  int _currentIndex = 0;

  static const int _tabCount = 5;

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
    await notifications.evaluate();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? AppColors.darkSurface
        : AppColors.lightBackground;

    final surface = isDark
        ? AppColors.darkSurface
        : AppColors.lightBackground;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    final cardDecoration = BoxDecoration(
      color: isDark
          ? AppColors.darkSurface
          : const Color.fromARGB(153, 255, 253, 249),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 40,
          offset: const Offset(0, -3),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: bg,

      body: SafeArea(
        child: Column(
          children: [

            // ================= HEADER =================

            Container(
              decoration: cardDecoration,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [

                    IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: textPrimary,
                      ),

                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                              themeNotifier:
                                  widget.themeNotifier,
                              onThemeChanged:
                                  widget.onThemeChanged,
                              appFlowController:
                                  widget.appFlowController,
                            ),
                          ),
                        );
                      },
                    ),

                    Text(
                      'Waffer',
                      style:
                          GoogleFonts.playfairDisplay(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // PAGES 

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: (_currentIndex == 1 || _currentIndex == 2)
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),

                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },

                children: [
                  const HomeScreen(),
                  const ReportScreen(),
                  const SavingsScreen(),
                  const PlaceholderScreen(label: 'شاشة 4'),
                  const NotificationsScreen(),
                ],
            ),
          ),

          // NAV BAR

            Container(
              decoration: BoxDecoration(
                color: surface,
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),

              padding:
                  const EdgeInsets.symmetric(
                vertical: 10,
              ),

              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,

                children:
                    List.generate(
                  _tabCount,
                  (index) {
                    final isSelected =
                        index == _currentIndex;

                    return GestureDetector(
                      onTap: () =>
                          _onTabTapped(index),

                      child: AnimatedScale(
                        scale:
                            isSelected ? 1.25 : 1.0,

                        duration:
                            const Duration(
                          milliseconds: 250,
                        ),

                        curve: Curves.easeOut,

                        child: index == 2
                            ? WafferWMark(
                                size: 26,
                                color: isSelected
                                    ? accent
                                    : textPrimary.withValues(alpha: 0.35),
                              )
                            : index == 4
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
                                            : Icons.circle_outlined,
                                    size: 26,
                                    color: isSelected
                                        ? accent
                                        : textPrimary.withValues(alpha: 0.35),
                                  ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
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
