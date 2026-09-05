import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/screens/offline/dashboard/dashboard_screen.dart';
import 'package:waffer/screens/offline/placeholder/placeholder.dart';
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    PlaceholderScreen(label: 'شاشة 2'),
    PlaceholderScreen(label: 'شاشة 3'),
    PlaceholderScreen(label: 'شاشة 4'),
    PlaceholderScreen(label: 'شاشة 5'),
  ];

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightBackground;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final accent = isDark ? const Color.fromARGB(255, 121, 168, 78) : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ===== Header =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: textPrimary),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            body: Center(child: Text('لاحقاً: الإعدادات')),
                          ),
                        ),
                      );
                    },
                  ),
                  Text(
                    'Waffer',
                    style: TextStyle(
                      fontSize:40,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'cairo',
                      color:accent,
                    ),
                  ),
                ],
              ),
            ),

            // ===== الشاشات (Slide) =====
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                children: _screens,
              ),
            ),

            // ===== Bottom Nav Bar =====
            Container(
              decoration: BoxDecoration(
                color: surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_screens.length, (index) {
                  final isSelected = index == _currentIndex;
                  return GestureDetector(
                    onTap: () => _onTabTapped(index),
                    child: AnimatedScale(
                      scale: isSelected ? 1.25 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: Icon(
                        index == 0 ? Icons.home_rounded : Icons.circle_outlined,
                        size: 26,
                        color: isSelected ? accent : textPrimary.withOpacity(0.35),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}