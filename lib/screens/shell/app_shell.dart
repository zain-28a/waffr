
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/screens/offline/dashboard/dashboard.dart';
import 'package:waffer/screens/offline/dashboard/home.dart';
import 'package:waffer/screens/offline/dashboard/monthly_spend_screen.dart';
import 'package:waffer/screens/offline/placeholder/placeholder.dart';
import 'package:waffer/screens/offline/reports_screen.dart';
import 'package:waffer/screens/offline/settings/settings_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class AppShell extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final VoidCallback onThemeChanged;

  const AppShell({
    super.key,
    required this.themeNotifier,
    required this.onThemeChanged,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final PageController _pageController =
      PageController(initialPage: 0);

  int _currentIndex = 0;

  static const int _tabCount = 5;

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

            // ================= PAGES =================

            Expanded(
              child: PageView(
                controller: _pageController,

                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },

                children: [
                  const HomeScreen(),
                  MonthlySpendScreen(isActive: _currentIndex == 1),
                  const ReportsScreen(),
                  const PlaceholderScreen(label: 'شاشة 4'),
                  const PlaceholderScreen(label: 'شاشة 5'),
                ],
              ),
            ),

            // ================= NAV BAR =================

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

                        child: Icon(
                          index == 0
                              ? Icons.home_rounded
                              : index == 1
                                  ? Icons.bar_chart_rounded
                                  : Icons.circle_outlined,

                          size: 26,

                          color: isSelected
                              ? accent
                              : textPrimary
                                  .withValues(alpha: 0.35),
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
