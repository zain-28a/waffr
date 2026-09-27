import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/data/services/backup_service.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_dirty.dart';
import 'package:waffer/core/sync/sync_service.dart';
import 'package:waffer/core/theme/app_theme.dart';
import 'package:waffer/screens/offline/applock/applockscreen.dart';
import 'package:waffer/screens/offline/login/login_screen.dart';
import 'package:waffer/screens/offline/theme_select_screen.dart';
import 'package:waffer/screens/shell/app_shell.dart';
import 'package:waffer/widgets/brand/waffer_logo.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

/// App entry: theme, first-launch flow, and the signed-in shell.
///
/// Preferences are loaded once in [AppPrefs] before [runApp], so later
/// screens read the cached handle instead of hitting disk on each build.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.warmUp();

  TransactionStore.instance.onHydrated =
      NotificationService.instance.seedIfNeeded;

  // Drive backup is currently disabled. Harmless no-op until re-enabled.
  unawaited(BackupService.instance.initialize());
  unawaited(SyncService.instance.initialize());

  runApp(const WafarApp());
}

/// Root widget. Holds the light/dark choice and waits until it is known.
class WafarApp extends StatefulWidget {
  const WafarApp({super.key});

  @override
  State<WafarApp> createState() => _WafarAppState();
}

/// Applies [WafarApp]'s theme notifier to [MaterialApp].
class _WafarAppState extends State<WafarApp> {
  final ValueNotifier<ThemeMode> _themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  /// Reads the saved theme. System mode is the default until the user picks one.
  Future<void> _loadTheme() async {
    final prefs = await AppPrefs.instance;
    _themeMode.value = _themeModeFromPrefs(prefs);

    setState(() {
      _themeLoaded = true;
    });
  }

  /// Persists light or dark. System mode is not written, so the next launch
  /// can follow the device again only when that key is absent.
  Future<void> _changeTheme(ThemeMode mode) async {
    _themeMode.value = mode;

    if (mode == ThemeMode.system) return;

    final prefs = await AppPrefs.instance;

    await prefs.setBool(
      'dark_mode',
      mode == ThemeMode.dark,
    );

    BackupService.instance.scheduleBackup();
    unawaited(SyncDirty.mark(settings: true));
  }

  /// Flips between the two explicit themes. Used by the settings toggle.
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
        home: WafferSplash(followPlatformBrightness: true),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'waffr',
          debugShowCheckedModeBanner: false,

          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

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

/// Chooses login, first-launch theme, app lock, or the main shell.
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

/// Gate state: login, theme pick, lock, then [AppShell].
class _AppFlowControllerState
    extends State<AppFlowController> with WidgetsBindingObserver {
  bool? _authChoiceMade;
  bool? _isFirstLaunch;
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
      if (_appLockEnabled == true && _isAuthenticated) {
        setState(() {
          _isAuthenticated = false;
        });
      }
    }
  }

  /// Loads the flags that decide which gate the user sees.
  Future<void> _checkAppState() async {
    final prefs = await AppPrefs.instance;

    final firstLaunch =
        prefs.getBool('first_launch') ?? true;

    final appLockEnabled =
        prefs.getBool('app_lock') ?? false;

    final authChoiceMade =
        prefs.getBool(BackupService.authChoiceKey) ?? !firstLaunch;

    if (!mounted) return;

    setState(() {
      _authChoiceMade = authChoiceMade;
      _isFirstLaunch = firstLaunch;
      _appLockEnabled = appLockEnabled;
      _isAuthenticated = false;
    });
  }

  /// Login finished. Re-read theme and flags in case a restore changed them.
  Future<void> _onAuthChoiceCompleted() async {
    await _syncThemeFromPrefs();
    await _checkAppState();
    unawaited(SyncService.instance.syncNow());
  }

  /// A Drive restore finished while we were open. Replay the login-completed path.
  void _onRemoteRestored() {
    unawaited(_onAuthChoiceCompleted());
  }

  /// Applies a theme that arrived from a restore while the app is open.
  Future<void> _syncThemeFromPrefs() async {
    final prefs = await AppPrefs.instance;
    final mode = _themeModeFromPrefs(prefs);

    if (mode != widget.themeMode) {
      widget.onThemeChanged(mode);
    }
  }

  /// Sign-out returns to login and leaves the local ledger in place.
  Future<void> returnToLogin() async {
    await AuthSession.instance.clearSession();
    final prefs = await AppPrefs.instance;
    await prefs.setBool(BackupService.authChoiceKey, false);
    if (!mounted) return;
    setState(() {
      _authChoiceMade = false;
      _isAuthenticated = false;
    });
  }

  /// First-launch theme screen is done; don't show it again.
  Future<void> _markFirstLaunchDone() async {
    final prefs = await AppPrefs.instance;

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

  /// Biometric lock succeeded for this foreground session.
  void _unlockApp() {
    if (!mounted) return;

    setState(() {
      _isAuthenticated = true;
    });
  }

  /// Settings changed the lock flag. Re-read it so the gate matches.
  /// [sessionAuthenticated] keeps this foreground session open after the
  /// user just confirmed device auth to turn the lock on.
  Future<void> refreshAppLockState({bool sessionAuthenticated = false}) async {
    final prefs = await AppPrefs.instance;
    final appLockEnabled = prefs.getBool('app_lock') ?? false;

    if (!mounted) return;

    setState(() {
      _appLockEnabled = appLockEnabled;
      if (sessionAuthenticated && appLockEnabled) {
        _isAuthenticated = true;
      } else if (!appLockEnabled) {
        _isAuthenticated = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authChoiceMade == null ||
        _isFirstLaunch == null ||
        _appLockEnabled == null) {
      return const WafferSplash();
    }

    // User has not chosen an account or guest mode yet.
    if (_authChoiceMade == false) {
      return LoginScreen(
        onCompleted: _onAuthChoiceCompleted,
      );
    }

    if (_isFirstLaunch == true) {
      return ThemeSelectScreen(
        onThemeChanged: widget.onThemeChanged,

        onContinue: () {
          unawaited(_markFirstLaunchDone());
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

/// No saved choice yet: follow the device. After a choice: the stored light or dark theme.
ThemeMode _themeModeFromPrefs(SharedPreferences prefs) {
  if (prefs.containsKey('dark_mode')) {
    return (prefs.getBool('dark_mode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  final firstLaunch = prefs.getBool('first_launch') ?? true;
  return firstLaunch ? ThemeMode.system : ThemeMode.light;
}