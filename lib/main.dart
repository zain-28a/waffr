import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffr/data/services/backup_service.dart';
import 'package:waffr/data/services/legacy_profile_photo.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_dirty.dart';
import 'package:waffr/core/sync/sync_service.dart';
import 'package:waffr/core/l10n/waffr_material_localizations.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/theme/app_theme.dart';
import 'package:waffr/screens/offline/applock/applockscreen.dart';
import 'package:waffr/screens/offline/login/login_screen.dart';
import 'package:waffr/screens/offline/theme_select_screen.dart';
import 'package:waffr/screens/shell/app_shell.dart';
import 'package:waffr/widgets/brand/waffr_logo.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

/// App entry: theme, first-launch flow, and the signed-in shell.
///
/// Preferences are loaded once in [AppPrefs] before [runApp], so later
/// screens read the cached handle instead of hitting disk on each build.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.warmUp();

  TransactionStore.instance.onHydrated =
      NotificationService.instance.seedIfNeeded;

  unawaited(SyncService.instance.initialize());
  unawaited(LegacyProfilePhoto.remove());
  _registerFontLicenses();

  runApp(const WafarApp());
}

// Bundled fonts are OFL-licensed; their notices must ship with the app.
// Package licenses are added by Flutter itself.
void _registerFontLicenses() {
  const fonts = <String, String>{
    'Tajawal': 'assets/licenses/Tajawal-OFL.txt',
    'Outfit': 'assets/licenses/Outfit-OFL.txt',
    'Bebas Neue': 'assets/licenses/BebasNeue-OFL.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in fonts.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks(<String>[entry.key], text);
    }
  });
}

/// Root widget. Holds the light/dark choice and waits until it is known.
class WafarApp extends StatefulWidget {
  /// Creates a [WafarApp].
  const WafarApp({super.key});

  @override
  State<WafarApp> createState() => _WafarAppState();
}

/// Applies [WafarApp]'s theme notifier to [MaterialApp].
class _WafarAppState extends State<WafarApp> {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    // Prefs are warmed before runApp, so the theme is usually known now and
    // the first frame is already the real app (no throwaway splash frame).
    final cached = AppPrefs.cached;
    if (cached != null) {
      _themeMode.value = _themeModeFromPrefs(cached);
      _themeLoaded = true;
    } else {
      _loadTheme();
    }
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

    await prefs.setBool('dark_mode', mode == ThemeMode.dark);

    unawaited(SyncDirty.mark(settings: true));
  }

  /// Flips between the two explicit themes. Used by the settings toggle.
  Future<void> _toggleTheme() async {
    final newMode = _themeMode.value == ThemeMode.dark
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
        home: WaffrSplash(followPlatformBrightness: true),
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
            // Arabic strings with 0-9 digits; must come before the global one.
            WaffrMaterialLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,

          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemBarsFor(Theme.of(context).brightness),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
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

  /// Creates a [AppFlowController].
  const AppFlowController({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onToggleTheme,
    required this.themeNotifier,
  });

  @override
  State<AppFlowController> createState() => _AppFlowControllerState();
}

/// Gate state: login, theme pick, lock, then [AppShell].
class _AppFlowControllerState extends State<AppFlowController>
    with WidgetsBindingObserver {
  bool? _authChoiceMade;
  bool? _isFirstLaunch;
  bool? _appLockEnabled;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackupService.instance.addRestoreListener(_onRemoteRestored);
    // Same as the theme: decide the first gate synchronously when prefs are
    // already cached, so startup does not cross-fade from a splash.
    final cached = AppPrefs.cached;
    if (cached != null) {
      _applyFlags(cached);
    } else {
      _checkAppState();
    }
  }

  // True once the shell has been shown; the lock then covers it instead of
  // replacing it, so tabs, scroll positions and animations survive a lock.
  bool _shellBuilt = false;

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
    if (!mounted) return;
    setState(() => _applyFlags(prefs));
  }

  void _applyFlags(SharedPreferences prefs) {
    final firstLaunch = prefs.getBool('first_launch') ?? true;

    final appLockEnabled = prefs.getBool('app_lock') ?? false;

    final authChoiceMade =
        prefs.getBool(BackupService.authChoiceKey) ?? !firstLaunch;

    _authChoiceMade = authChoiceMade;
    _isFirstLaunch = firstLaunch;
    _appLockEnabled = appLockEnabled;
    _isAuthenticated = false;
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

    await prefs.setBool('first_launch', false);

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

  _FlowStage get _stage {
    if (_authChoiceMade == null ||
        _isFirstLaunch == null ||
        _appLockEnabled == null) {
      return _FlowStage.splash;
    }
    // User has not chosen an account or guest mode yet.
    if (_authChoiceMade == false) return _FlowStage.login;
    if (_isFirstLaunch == true) return _FlowStage.themeSelect;
    if (_appLockEnabled == true && !_isAuthenticated) return _FlowStage.lock;
    return _FlowStage.shell;
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final locked = stage == _FlowStage.lock;
    if (stage == _FlowStage.shell) _shellBuilt = true;

    // While locked, the page underneath stays the (hidden, paused) shell
    // when it was already built, instead of being thrown away.
    final baseStage = locked && _shellBuilt ? _FlowStage.shell : stage;

    final Widget page = switch (baseStage) {
      _FlowStage.splash => const WaffrSplash(),
      _FlowStage.login => LoginScreen(onCompleted: _onAuthChoiceCompleted),
      _FlowStage.themeSelect => ThemeSelectScreen(
        onThemeChanged: widget.onThemeChanged,
        onContinue: () {
          unawaited(_markFirstLaunchDone());
        },
      ),
      _FlowStage.lock => const SizedBox.expand(),
      _FlowStage.shell => Offstage(
        // Not painted while locked, so the ledger never shows behind the
        // lock (or in the app switcher), and its tickers are paused.
        offstage: locked,
        child: TickerMode(
          enabled: !locked,
          child: AppShell(
            themeNotifier: widget.themeNotifier,
            onThemeChanged: widget.onToggleTheme,
            appFlowController: this,
          ),
        ),
      ),
    };

    final switcher = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.slow),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey<_FlowStage>(baseStage), child: page),
    );

    // The lock covers everything at once, with no fade.
    return Stack(
      fit: StackFit.expand,
      children: [
        switcher,
        if (locked) LockScreen(onAuthenticated: _unlockApp),
      ],
    );
  }
}

/// Status and navigation bar icons that stay readable on the app background.
SystemUiOverlayStyle _systemBarsFor(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: brightness,
    systemNavigationBarColor: dark
        ? AppColors.darkBackground
        : AppColors.lightBackground,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}

/// Gates shown by [AppFlowController], in the order they are checked.
enum _FlowStage { splash, login, themeSelect, lock, shell }

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
