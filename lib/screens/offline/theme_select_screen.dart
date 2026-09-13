import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/button/ani_pri_button.dart';

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
  bool _isDark = false; //light by default

  void _toggle(bool value) {
  setState(() => _isDark = value);
  print('THEME SELECT: sending ${_isDark ? "dark" : "light"}');
  widget.onThemeChanged(_isDark ? ThemeMode.dark : ThemeMode.light);
}

  @override
  Widget build(BuildContext context) {
    final bg = _isDark ? const Color.fromARGB(255, 24, 24, 24) : AppColors.lightBackground;
    final surface = _isDark ? AppColors.darkSurface : AppColors.lightSurface;
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
                  fontFamily: 'Cairo',
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
                style: TextStyle(color: textSecondary, fontSize: 18),
                child: const Text(
                  "يمكن تغييره لاحقا من الاعدادات",
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
                      _isDark ? 'غامق' : 'فاتح',
                      key: ValueKey(_isDark),
                      style: TextStyle(color: textPrimary, fontSize: 20),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 0),

              SizedBox(
                width: 500,
                child: AnimatedPrimaryButton(
  text: 'متابعة',
  backgroundColor: accent,
  textColor: surface,
                  style: TextStyle(color: surface, fontSize: 18, fontWeight: FontWeight.bold),
  onPressed: widget.onContinue,
)
              ),
              
            ], 
          ),
        ),
      ),
    ));
  }
}