import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app theme.dart';
import 'package:waffer/screens/offline/applock/applockscreen.dart';
import 'package:waffer/screens/offline/login/login_screen.dart';
import 'package:waffer/screens/offline/user_info/user_info_screen.dart';
import 'package:waffer/screens/offline/theme_select_screen.dart';
import 'package:waffer/screens/shell/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  TransactionStore.instance.onHydrated =
      NotificationService.instance.seedIfNeeded;

  // مزامنة انتهازية مع Drive. لا تحجب الإقلاع ولا تُظهر أخطاء.
  unawaited(BackupService.instance.initialize());

  runApp(const WafarApp());
}

class WafarApp extends StatefulWidget {
  const WafarApp({super.key});

  @override
  State<WafarApp> createState() => _WafarAppState();
}

class _WafarAppState extends State<WafarApp> {
  final ValueNotifier<ThemeMode> _themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final isDark = prefs.getBool('dark_mode') ?? false;

    _themeMode.value =
        isDark ? ThemeMode.dark : ThemeMode.light;

    setState(() {
      _themeLoaded = true;
    });
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    _themeMode.value = mode;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'dark_mode',
      mode == ThemeMode.dark,
    );

    BackupService.instance.scheduleBackup();
  }

  Future<void> _toggleTheme() async {
    final newMode =
        _themeMode.value == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark;

    await _changeTheme(newMode);
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_themeLoaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox.shrink(),
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'Waffer 1.2.0',
          debugShowCheckedModeBanner: false,

          locale: const Locale('ar'),

          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,

          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            );
          },

          home: AppFlowController(
            themeMode: themeMode,
            onThemeChanged: _changeTheme,
            onToggleTheme: _toggleTheme,
            themeNotifier: _themeMode,
          ),
        );
      },
    );
  }
}

class AppFlowController extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onToggleTheme;
  final ValueNotifier<ThemeMode> themeNotifier;

  const AppFlowController({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onToggleTheme,
    required this.themeNotifier,
  });

  @override
  State<AppFlowController> createState() =>
      _AppFlowControllerState();
}

class _AppFlowControllerState
    extends State<AppFlowController> with WidgetsBindingObserver {
  bool? _authChoiceMade;
  bool? _isFirstLaunch;
  bool? _userInfoCompleted;
  bool? _appLockEnabled;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackupService.instance.addRestoreListener(_onRemoteRestored);
    _checkAppState();
  }

  @override
  void dispose() {
    BackupService.instance.removeRestoreListener(_onRemoteRestored);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App went to background
      if (_appLockEnabled == true && _isAuthenticated) {
        setState(() {
          _isAuthenticated = false;
        });
      }
    }
  }

  Future<void> _checkAppState() async {
    final prefs = await SharedPreferences.getInstance();

    final firstLaunch =
        prefs.getBool('first_launch') ?? true;

    final userInfoCompleted =
        prefs.getBool('user_info_completed') ?? false;

    final appLockEnabled =
        prefs.getBool('app_lock') ?? false;

    // التثبيتات القديمة تجاوزت الإعداد أصلاً، فلا تُعرض عليها شاشة الدخول.
    final authChoiceMade =
        prefs.getBool(BackupService.authChoiceKey) ?? !firstLaunch;

    if (!mounted) return;

    setState(() {
      _authChoiceMade = authChoiceMade;
      _isFirstLaunch = firstLaunch;
      _userInfoCompleted = userInfoCompleted;
      _appLockEnabled = appLockEnabled;
      _isAuthenticated = false;
    });
  }

  /// بعد اختيار المستخدم في شاشة الدخول.
  ///
  /// إذا استُعيدت نسخة احتياطية فقد تغيّرت المفاتيح المحفوظة،
  /// لذا يُعاد قراءة المظهر وحالة التطبيق من جديد.
  Future<void> _onAuthChoiceCompleted() async {
    await _syncThemeFromPrefs();
    await _checkAppState();
  }

  void _onRemoteRestored() {
    unawaited(_onAuthChoiceCompleted());
  }

  Future<void> _syncThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final mode = (prefs.getBool('dark_mode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;

    if (mode != widget.themeMode) {
      widget.onThemeChanged(mode);
    }
  }

  Future<void> _markUserInfoCompleted() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'user_info_completed',
      true,
    );

    BackupService.instance.scheduleBackup();

    if (!mounted) return;

    setState(() {
      _userInfoCompleted = true;
    });
  }

  Future<void> _markFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'first_launch',
      false,
    );

    BackupService.instance.scheduleBackup();

    if (!mounted) return;

    setState(() {
      _isFirstLaunch = false;
    });
  }

  void _unlockApp() {
    if (!mounted) return;

    setState(() {
      _isAuthenticated = true;
    });
  }

  Future<void> refreshAppLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final appLockEnabled = prefs.getBool('app_lock') ?? false;

    if (!mounted) return;

    setState(() {
      _appLockEnabled = appLockEnabled;
      if (!appLockEnabled) {
        _isAuthenticated = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authChoiceMade == null ||
        _isFirstLaunch == null ||
        _userInfoCompleted == null ||
        _appLockEnabled == null) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }

    // المستخدم لم يختر بعد بين حساب Google ووضع الضيف
    if (_authChoiceMade == false) {
      return LoginScreen(
        onCompleted: _onAuthChoiceCompleted,
      );
    }

    // المستخدم لم يدخل معلوماته
    if (_userInfoCompleted == false) {
      return UserInfoScreen(
        onContinue: () async {
          await _markUserInfoCompleted();
        },
      );
    }

    
    if (_isFirstLaunch == true) {
      return ThemeSelectScreen(
        onThemeChanged: widget.onThemeChanged,

        onContinue: () async {
          await _markFirstLaunchDone();

          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AppShell(
                themeNotifier: widget.themeNotifier,
                onThemeChanged: widget.onToggleTheme,
                appFlowController: this,
              ),
            ),
          );
        },
      );
    }

    if (_appLockEnabled == true && !_isAuthenticated) {
      return LockScreen(
        onAuthenticated: _unlockApp,
      );
    }

    return AppShell(
      themeNotifier: widget.themeNotifier,
      onThemeChanged: widget.onToggleTheme,
      appFlowController: this,
    );
  }
}