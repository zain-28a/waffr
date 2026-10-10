// App settings: account, income, currencies, theme, app lock, privacy, help, reset.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/data/services/backup_service.dart';
import 'package:waffr/data/stores/expense_preset_store.dart';
import 'package:waffr/data/stores/category_store.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/profile_photo.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/recurring_expense_store.dart';
import 'package:waffr/data/stores/shopping_list_store.dart';
import 'package:waffr/data/models/transaction.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/sync/sync_service.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/login/login_screen.dart';
import 'package:waffr/screens/offline/settings/account_screen.dart';
import 'package:waffr/screens/offline/settings/ai_permissions_screen.dart';
import 'package:waffr/screens/offline/settings/help_screen.dart';
import 'package:waffr/screens/offline/settings/privacy_security_screen.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/screens/offline/settings/sheets/currencies_sheet.dart';
import 'package:waffr/screens/offline/settings/sheets/monthly_income_sheet.dart';
import 'package:waffr/widgets/brand/profile_avatar.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/dialogs/edit_amount_dialog.dart';
import 'package:waffr/core/prefs/app_prefs.dart';

// Hub for account, appearance, security shortcuts, and destructive data reset.
class SettingsScreen extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final VoidCallback onThemeChanged;
  final dynamic appFlowController;

  const SettingsScreen({
    super.key,
    required this.themeNotifier,
    required this.onThemeChanged,
    required this.appFlowController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appLock = false;
  bool _isAuthenticating = false;

  String _userName = '';
  String _userEmail = '';
  bool _loggedIn = false;
  String? _photoPath;

  bool _hasMonthlyIncome = false;
  bool _hasWeeklyIncome = false;
  double _monthlyIncome = 0;
  double _weeklyIncome = 0;
  // Weekly income stays in the store; the settings tile is hidden for now.
  static const bool _weeklyIncomeChoiceEnabled = false;

  final LocalAuthentication _auth = LocalAuthentication();
  final ValueNotifier<bool> _headerElevated = ValueNotifier(false);

  @override
  void initState() {
    super.initState();

    widget.themeNotifier.addListener(_onThemeChanged);

    _loadSettings();
  }

  @override
  void dispose() {
    widget.themeNotifier.removeListener(_onThemeChanged);
    _headerElevated.dispose();

    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // Pulls prefs, auth session, profile photo, and configured income into state.
  Future<void> _loadSettings() async {
    final prefs = await AppPrefs.instance;
    await TransactionStore.instance.ensureLoaded();

    final store = TransactionStore.instance;
    final accountEmail = await AuthSession.instance.email() ?? '';
    final loggedIn = await AuthSession.instance.isLoggedIn();
    final photoPath = await ProfilePhoto.path();

    if (!mounted) return;

    setState(() {
      _appLock = prefs.getBool('app_lock') ?? false;

      _loggedIn = loggedIn;
      _photoPath = photoPath;

      _userName = prefs.getString('user_name') ?? '';

      _userEmail = loggedIn
          ? accountEmail
          : (prefs.getString('user_email') ?? '');

      _hasMonthlyIncome = store.hasConfiguredMonthlyIncome;
      _hasWeeklyIncome = store.hasWeeklyIncome;
      _monthlyIncome = store.configuredMonthlyIncome ?? 0;
      _weeklyIncome = store.referenceIncome(RecurringFrequency.weekly);
    });
  }

  // Enables lock only after device auth succeeds; disable writes prefs immediately.
  Future<void> _toggleAppLock(bool value) async {
    if (_isAuthenticating) return;

    if (value) {
      setState(() {
        _isAuthenticating = true;
      });

      try {
        final supported = await _auth.isDeviceSupported();

        if (!supported) {
          if (!mounted) return;

          showAppSnackBar(
            context,
            'جهازك لا يدعم البصمة أو قفل الشاشة',
            kind: AppFeedbackKind.warning,
          );

          setState(() {
            _isAuthenticating = false;
          });

          return;
        }

        final authenticated = await _auth.authenticate(
          localizedReason: 'تفعيل قفل التطبيق',
          biometricOnly: false,
        );

        if (!mounted) return;

        if (authenticated) {
          final prefs = await AppPrefs.instance;
          await prefs.setBool('app_lock', true);

          BackupService.instance.scheduleBackup();

          setState(() {
            _appLock = true;
          });

          widget.appFlowController?.refreshAppLockState(
            sessionAuthenticated: true,
          );

          if (mounted) {
            showAppSnackBar(context, 'تم تفعيل قفل التطبيق', success: true);
          }
        }
      } on LocalAuthException catch (_) {
      } catch (_) {
      } finally {
        if (mounted) {
          setState(() {
            _isAuthenticating = false;
          });
        }
      }
    } else {
      final prefs = await AppPrefs.instance;
      await prefs.setBool('app_lock', false);

      BackupService.instance.scheduleBackup();

      if (!mounted) return;

      setState(() {
        _appLock = false;
      });

      if (widget.appFlowController != null) {
        widget.appFlowController.refreshAppLockState();
      }

      if (mounted) {
        showAppSnackBar(context, 'تم إيقاف قفل التطبيق', success: true);
      }
    }
  }

  // Explains that Arabic is currently the only supported language.
  void _showLanguageInfo() {
    showAppInfoDialog(
      context,
      title: 'اللغة',
      message:
          'العربية هي اللغة الوحيدة المتاحة حالياً. نعمل على إضافة لغات أخرى في التحديثات القادمة.',
    );
  }

  // Signed-in users open AccountScreen; guests go through LoginScreen first.
  Future<void> _openAccount() async {
    if (_loggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AccountScreen(
            onSignedOut: () async {
              await widget.appFlowController?.returnToLogin();
            },
          ),
        ),
      );
      if (!mounted) return;
      await _loadSettings();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          allowGuest: false,
          popOnSuccess: true,
          onCompleted: () async {
            await SyncService.instance.syncNow();
          },
        ),
      ),
    );

    if (!mounted) return;
    await _loadSettings();
  }

  // Edit or clear preferred monthly/weekly income in a sheet, not a dialog.
  Future<void> _editIncome(RecurringFrequency frequency) async {
    final isMonthly = frequency == RecurringFrequency.monthly;
    final current = isMonthly ? _monthlyIncome : _weeklyIncome;

    final result = await showMonthlyIncomeSheet(
      context,
      title: isMonthly ? 'الدخل الشهري' : 'الدخل الأسبوعي',
      initialAmount: current,
      allowClear: isMonthly && current > 0,
    );

    if (!mounted || result == null) return;

    if (result is AmountDialogCleared) {
      final cleared = await TransactionStore.instance.clearPreferredIncomeAmount(
        frequency: frequency,
        currencyCode: result.currencyCode,
      );
      if (!mounted) return;
      if (!cleared) {
        showAppSnackBar(context, 'تعذّر إزالة الدخل. حاول مرة أخرى.');
        return;
      }
      await _loadSettings();
      if (!mounted) return;
      showAppSnackBar(
        context,
        isMonthly ? 'تمت إزالة الدخل الشهري' : 'تمت إزالة الدخل الأسبوعي',
        success: true,
      );
      return;
    }

    if (result is! EditAmountResult) return;
    final amount = result.amount;

    final saved = await TransactionStore.instance.setPreferredIncomeAmount(
      frequency: frequency,
      amount: amount,
      currencyCode: result.currencyCode,
    );

    if (!mounted) return;

    if (!saved) {
      showAppSnackBar(context, 'تعذّر حفظ الدخل. حاول مرة أخرى.');
      return;
    }

    await _loadSettings();
    if (!mounted) return;

    showAppSnackBar(
      context,
      isMonthly ? 'تم حفظ دخلك الشهري' : 'تم حفظ دخلك الأسبوعي',
      success: true,
    );
  }

  void _showAbout() {
    showAppInfoDialog(
      context,
      title: 'عن وفّر',
      message:
          'وفّر يساعدك على تنظيم دخلك ومصروفاتك والتزاماتك، والتوفير لأهدافك. '
          'بياناتك المالية تُحفظ على جهازك، ويمكنك مزامنتها مع حسابك متى شئت.',
    );
  }

  // Clears prefs, session, photo, and in-memory stores, then returns to first route.
  Future<void> _resetApp() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'إعادة ضبط التطبيق',
      message: 'ستُحذف بياناتك الشخصية ورصيدك وسجل المصروفات من هذا الجهاز. لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف البيانات',
      destructive: true,
    );

    if (confirm != true) return;

    final prefs = await AppPrefs.instance;

    await prefs.clear();
    await AuthSession.instance.clearSession();
    await AuthSession.instance.clearDataOwner();
    await ProfilePhoto.clear();

    TransactionStore.instance.resetCache();
    CurrencyStore.instance.resetCache();
    NotificationService.instance.resetCache();
    UsageStreakService.instance.resetCache();
    ProfileIdentity.instance.reset();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();
    ExpensePresetStore.instance.resetCache();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeNotifier.value == ThemeMode.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;

    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            WaffrBackHeader(
              applySafeArea: false,
              elevated: _headerElevated,
              title: 'الإعدادات',
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth != 0) return false;
                  final next = notification.metrics.pixels > 6;
                  if (_headerElevated.value != next) {
                    _headerElevated.value = next;
                  }
                  return false;
                },
                child: ListView(
        padding: const EdgeInsets.all(20),

        children: [
          _SectionTitle(title: 'الحساب', color: textSecondary),

          GestureDetector(
            onTap: _openAccount,
            child: _ProfileCard(
              name: _loggedIn
                  ? (_userName.isEmpty ? 'حساب وفّر' : _userName)
                  : 'لا يوجد حساب',
              email: _loggedIn
                  ? _userEmail
                  : 'اضغط لتسجيل الدخول أو إنشاء حساب',
              photoPath: _photoPath,
              accent: accent,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              placeholder: !_loggedIn,
            ),
          ),

          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.payments_outlined,
            title: 'الدخل الشهري',
            subtitle: _hasMonthlyIncome
                ? '${formatMoney(_monthlyIncome)} $currencyLabel'
                : 'لم يُحدَّد بعد',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => _editIncome(RecurringFrequency.monthly),
          ),

          if (_weeklyIncomeChoiceEnabled && _hasWeeklyIncome) ...[
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.date_range_outlined,
              title: 'الدخل الأسبوعي',
              subtitle: '${formatMoney(_weeklyIncome)} $currencyLabel',
              accent: accent,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () => _editIncome(RecurringFrequency.weekly),
            ),
          ],

          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.currency_exchange_rounded,
            title: 'العملات',
            subtitle: 'إضافة عملة أو اختيار العملة النشطة',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => showCurrenciesSheet(context),
          ),

          const SizedBox(height: 12),
          _SettingsTile(
            icon: Icons.event_repeat_rounded,
            title: 'الالتزامات',
            subtitle: 'المصروفات المتكررة وطريقة خصمها',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => showObligationsSheet(context),
          ),

          const SizedBox(height: 25),

          _SectionTitle(title: 'المظهر', color: textSecondary),

          _SettingsTile(
            icon: Icons.dark_mode_outlined,

            title: 'الوضع الداكن',

            subtitle: isDark ? 'مفعّل' : 'غير مفعّل',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            trailing: Switch(
              value: isDark,
              activeThumbColor: accent,

              onChanged: (_) {
                widget.onThemeChanged();
              },
            ),

            onTap: widget.onThemeChanged,
          ),

          const SizedBox(height: 12),

          _SettingsTile(
            icon: Icons.language_rounded,

            title: 'اللغة',

            subtitle: 'العربية (اللغة الوحيدة المتاحة)',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: _showLanguageInfo,
          ),

          const SizedBox(height: 25),

          _SectionTitle(title: 'الحماية والخصوصية', color: textSecondary),

          _SettingsTile(
            icon: Icons.lock_outline_rounded,

            title: 'قفل التطبيق',

            subtitle: 'طلب البصمة أو رمز الجهاز عند فتح وفّر',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            trailing: Switch(
              value: _appLock,
              activeThumbColor: accent,

              onChanged: _toggleAppLock,
            ),

            onTap: () => _toggleAppLock(!_appLock),
          ),

          const SizedBox(height: 12),

          _SettingsTile(
            icon: Icons.auto_graph_rounded,

            title: 'أذونات الذكاء الاصطناعي',

            subtitle: 'لا توجد أذونات متاحة حالياً',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AIPermissionsScreen()),
              );
            },
          ),

          const SizedBox(height: 12),

          _SettingsTile(
            icon: Icons.privacy_tip_outlined,

            title: 'الخصوصية والأمان',

            subtitle: 'البيانات والمزامنة وحماية الجهاز',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivacySecurityScreen(
                    appFlowController: widget.appFlowController,
                  ),
                ),
              );
              await _loadSettings();
            },
          ),

          const SizedBox(height: 25),

          _SectionTitle(title: 'الدعم', color: textSecondary),

          _SettingsTile(
            icon: Icons.help_outline_rounded,

            title: 'المساعدة',

            subtitle: 'الأسئلة الشائعة والدعم',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HelpScreen()));
            },
          ),

          const SizedBox(height: 12),

          _SettingsTile(
            icon: Icons.info_outline_rounded,

            title: 'عن وفّر',

            subtitle: 'معلومات عن التطبيق',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: _showAbout,
          ),

          const SizedBox(height: 25),

          if (!_loggedIn) ...[
            _SectionTitle(title: 'البيانات', color: textSecondary),

            _SettingsTile(
              icon: Icons.delete_outline_rounded,

              title: 'إعادة ضبط التطبيق',

              subtitle: 'حذف جميع البيانات والبدء من جديد',

              accent: accent,
              surface: surface,

              textPrimary: textPrimary,

              textSecondary: textSecondary,

              onTap: _resetApp,
            ),

            const SizedBox(height: 30),
          ] else
            const SizedBox(height: 5),

          Center(
            child: Text(
              'waffr 2.10.0',

              style: TextStyle(
                color: textSecondary.withValues(alpha: 0.6),

                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Avatar + name/email card at the top of settings (or a sign-in prompt).
class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String? photoPath;
  final bool placeholder;

  final Color accent;
  final Color surface;

  final Color textPrimary;
  final Color textSecondary;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    this.photoPath,
    this.placeholder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(25),
      ),

      child: Row(
        children: [
          ProfileAvatar(
            photoPath: photoPath,
            accent: accent,
            radius: 27,
            placeholder: placeholder,
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  name.isEmpty ? 'المستخدم' : name,

                  style: TextStyle(
                    color: textPrimary,

                    fontSize: 17,

                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (email.isNotEmpty)
                  Text(
                    email,

                    textDirection: TextDirection.ltr,

                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Small uppercase section label above a group of tiles.
class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) => AppSectionTitle(title: title);
}

// Standard settings row: icon, title, subtitle, optional trailing control.
// Kept so the call sites stay short; the look lives in AppListTile.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

