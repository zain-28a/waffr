import 'package:flutter/material.dart';
import 'package:waffer/widgets/button/app_primary_button.dart';
import 'package:waffer/core/theme/app_color.dart';

// First-launch light/dark picker before entering the app.

class ThemeSelectScreen extends StatefulWidget {
  final void Function(ThemeMode mode) onThemeChanged;
  final VoidCallback onContinue;

  const ThemeSelectScreen({
    super.key,
    required this.onThemeChanged,
    required this.onContinue,
  });

  @override
  State<ThemeSelectScreen> createState() => _ThemeSelectScreenState();
}

class _ThemeSelectScreenState extends State<ThemeSelectScreen> {
  late bool _isDark;

  @override
  void initState() {
    super.initState();
    _isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _toggle(bool value) {
    setState(() => _isDark = value);
    widget.onThemeChanged(_isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void _continue() {
    widget.onThemeChanged(_isDark ? ThemeMode.dark : ThemeMode.light);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _isDark ? const Color.fromARGB(255, 24, 24, 24) : AppColors.lightBackground;
    final textPrimary = _isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = _isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = _isDark ? const Color.fromARGB(255, 121, 168, 78) : const Color.fromARGB(255, 64, 106, 38);

    return Scaffold(body: AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      color: bg,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [Column(children: [const SizedBox(height: 100),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                 style: TextStyle(
                  color: textPrimary,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                ),
                child:Text.rich(
                  TextSpan(children:[
                  const TextSpan( text:'اختر مظهر ',
                  style: TextStyle(fontWeight: FontWeight(266)),
                  
                ),
                TextSpan(text: "وفّر",style: TextStyle(fontWeight: const FontWeight(850),color: accent),),
                  ],),
                
                
              textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 18,
                  fontFamily: 'Outfit',
                  fontFamilyFallback: const ['Tajawal'],
                ),
                child: const Text(
                  'يمكنك تغييره لاحقاً من الإعدادات',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 170),]),

              
              Column(
                children: [
                  Switch(
                    value: _isDark,
                    onChanged: _toggle,
                    activeThumbColor: accent,
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _isDark ? 'داكن' : 'فاتح',
                      key: ValueKey(_isDark),
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 20,
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 0),

              SizedBox(
                width: 500,
                child: AppPrimaryButton(
                  label: 'متابعة',
                  onTap: _continue,
                )
              ),
              
            ], 
          ),
        ),
      ),
    ));
  }
}
