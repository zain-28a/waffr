import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/theme/app%20theme.dart';
import 'package:waffer/screens/offline/theme_select_screen.dart';
import 'package:waffer/screens/shell/app_shell.dart';

void main() {
  runApp(const WafarApp());
}

class WafarApp extends StatefulWidget {
  const WafarApp({super.key});

  @override
  State<WafarApp> createState() => _WafarAppState();
}

class _WafarAppState extends State<WafarApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waffer',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: AppFlowController(onThemeChanged: toggleTheme),
    );
  }
}

/// يقرر: أول مرة ولا لأ، وبيبني السلسلة المناسبة
class AppFlowController extends StatefulWidget {
  final void Function(ThemeMode mode) onThemeChanged;

  const AppFlowController({super.key, required this.onThemeChanged});

  @override
  State<AppFlowController> createState() => _AppFlowControllerState();
}

class _AppFlowControllerState extends State<AppFlowController> {
  bool? _isFirstLaunch;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirst = prefs.getBool('first_launch') ?? true;
    setState(() => _isFirstLaunch = isFirst);
  }

  Future<void> _markFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstLaunch == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_isFirstLaunch == true) {
      return ThemeSelectScreen(
        onThemeChanged: widget.onThemeChanged,
        onContinue: () async {
          await _markFirstLaunchDone();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AppShell()),
          );
        },
      );
    }

    return const AppShell();
  }
}