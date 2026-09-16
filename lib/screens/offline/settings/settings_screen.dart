import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/data/category_store.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/recurring_expense_store.dart';
import 'package:waffer/core/data/shopping_list_store.dart';
import 'package:waffer/core/data/transaction.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/screens/offline/login/login_screen.dart';
import 'package:waffer/screens/offline/settings/account_screen.dart';
import 'package:waffer/screens/offline/settings/ai_permissions_screen.dart';
import 'package:waffer/screens/offline/settings/help_screen.dart';
import 'package:waffer/screens/offline/settings/privacy_info_screen.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

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
  String? _googlePhotoUrl;

  bool _googleLinked = false;
  String _googleEmail = '';
  bool _hasMonthlyIncome = false;
  bool _hasWeeklyIncome = false;
  double _monthlyIncome = 0;
  double _weeklyIncome = 0;
  /// الدخل الأسبوعي يبقى في المنطق، لكنه مخفي مؤقتاً من خيارات المستخدم.
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await TransactionStore.instance.ensureLoaded();

    final store = TransactionStore.instance;
    final linkedEmail = prefs.getString(BackupService.linkedEmailKey) ?? '';
    final accounts = await BackupService.instance.linkedAccounts();

    LinkedGoogleAccount? current;
    for (final account in accounts) {
      if (account.email == linkedEmail) {
        current = account;
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      _appLock = prefs.getBool('app_lock') ?? false;

      _googleLinked = prefs.getBool(BackupService.linkedKey) ?? false;

      _googleEmail = linkedEmail;

      _googlePhotoUrl = prefs.getString(BackupService.linkedPhotoKey) ??
          current?.photoUrl;

      _userName = current?.displayName ?? prefs.getString('user_name') ?? '';

      _userEmail = _googleLinked
          ? _googleEmail
          : (prefs.getString('user_email') ?? '');

      _hasMonthlyIncome = store.hasMonthlyIncome;
      _hasWeeklyIncome = store.hasWeeklyIncome;
      _monthlyIncome = store.referenceIncome(RecurringFrequency.monthly);
      _weeklyIncome = store.referenceIncome(RecurringFrequency.weekly);
    });
  }

  Future<void> _toggleAppLock(bool value) async {
    if (_isAuthenticating) return;

    if (value) {
      // Enabling app lock - authenticate immediately
      setState(() {
        _isAuthenticating = true;
      });

      try {
        final supported = await _auth.isDeviceSupported();

        if (!supported) {
          if (!mounted) return;

          showAppSnackBar(context, 'جهازك لا يدعم المصادقة البيومترية');

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
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('app_lock', true);

          BackupService.instance.scheduleBackup();

          setState(() {
            _appLock = true;
          });

          // Mark as authenticated in the flow controller
          if (widget.appFlowController != null) {
            widget.appFlowController._isAuthenticated = true;
            widget.appFlowController.refreshAppLockState();
          }

          if (mounted) {
            showAppSnackBar(context, 'تم تفعيل قفل التطبيق', success: true);
          }
        }
      } on LocalAuthException catch (_) {
        // User cancelled
      } catch (_) {
        // Other error
      } finally {
        if (mounted) {
          setState(() {
            _isAuthenticating = false;
          });
        }
      }
    } else {
      // Disabling app lock
      final prefs = await SharedPreferences.getInstance();
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

  void _showLanguageInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: kSheetBarrierColor,

      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: surface,

            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),

          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Container(
                width: 45,
                height: 5,

                decoration: BoxDecoration(
                  color: textPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 25),

              Icon(Icons.language_rounded, color: accent, size: 50),

              const SizedBox(height: 18),

              Text(
                'اللغة',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                  fontFamily: 'Tajawal',
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'العربية هي اللغة الوحيدة المتاحة حالياً',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 15,
                  color: textSecondary,
                  fontFamily: 'Tajawal',
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'نعمل على إضافة المزيد من اللغات في التحديثات القادمة.',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 14,
                  color: textSecondary,
                  fontFamily: 'Tajawal',
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: Text(
                    'حسناً',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAccount() async {
    if (_googleLinked) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountScreen()),
      );
      await _loadSettings();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onCompleted: () async {
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    await _loadSettings();
  }

  Future<void> _editIncome(RecurringFrequency frequency) async {
    final isMonthly = frequency == RecurringFrequency.monthly;
    final current = isMonthly ? _monthlyIncome : _weeklyIncome;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    final amount = await showDialog<double>(
      context: context,
      builder: (context) => _EditIncomeDialog(
        title: isMonthly ? 'الدخل الشهري' : 'الدخل الأسبوعي',
        initialAmount: current,
        accent: accent,
      ),
    );

    if (!mounted || amount == null) return;

    final saved = await TransactionStore.instance.setPreferredIncomeAmount(
      frequency: frequency,
      amount: amount,
    );

    if (!mounted) return;

    if (!saved) {
      showAppSnackBar(context, 'تعذر حفظ الدخل. حاول مرة أخرى.');
      return;
    }

    setState(() {
      if (isMonthly) {
        _monthlyIncome = amount;
        _hasMonthlyIncome = true;
      } else {
        _weeklyIncome = amount;
        _hasWeeklyIncome = true;
      }
    });

    showAppSnackBar(
      context,
      isMonthly ? 'تم حفظ دخلك الشهري' : 'تم حفظ دخلك الأسبوعي',
      success: true,
    );
  }

  void _showAbout() {}

  Future<void> _resetApp() async {
    final confirm = await showDialog<bool>(
      context: context,

      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          title: const Text('إعادة ضبط التطبيق'),

          content: const Text(
            'سيتم حذف بيانات المستخدم والرصيد وسجل المصاريف. هل أنت متأكد؟',
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),

              child: const Text('إلغاء'),
            ),

            TextButton(
              onPressed: () => Navigator.pop(context, true),

              child: Text(
                'حذف البيانات',

                style: TextStyle(
                  color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.clear();

    TransactionStore.instance.resetCache();
    NotificationService.instance.resetCache();
    ShoppingListStore.instance.resetCache();
    RecurringExpenseStore.instance.resetCache();
    CategoryStore.instance.resetCache();

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
            WafferPageHeader(
              centerTitle: true,
              elevated: _headerElevated,
              leading: IconButton(
                icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'الإعدادات',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
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
              name: _googleLinked
                  ? (_userName.isEmpty ? 'حساب Google' : _userName)
                  : 'لا يوجد حساب',
              email: _googleLinked
                  ? _userEmail
                  : 'اضغط لتسجيل الدخول أو إنشاء حساب',
              photoUrl: _googleLinked ? _googlePhotoUrl : null,
              accent: accent,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              placeholder: !_googleLinked,
            ),
          ),

          if (_hasMonthlyIncome) ...[
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.payments_outlined,
              title: 'الدخل الشهري',
              subtitle: '${formatMoney(_monthlyIncome)} $currencyLabel',
              accent: accent,
              surface: surface,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              onTap: () => _editIncome(RecurringFrequency.monthly),
            ),
          ],

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

          const SizedBox(height: 25),

          _SectionTitle(title: 'المظهر', color: textSecondary),

          _SettingsTile(
            icon: Icons.dark_mode_outlined,

            title: 'الوضع الداكن',

            subtitle: isDark ? 'مفعل' : 'غير مفعل',

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

            subtitle: 'استخدام حماية الجهاز عند فتح وفر',

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

            title: 'الخصوصية والبيانات',

            subtitle: 'كيف يتم حماية بياناتك',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyInfoScreen()),
              );
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

            title: 'عن وفر',

            subtitle: 'معلومات عن التطبيق',

            accent: accent,
            surface: surface,

            textPrimary: textPrimary,

            textSecondary: textSecondary,

            onTap: _showAbout,
          ),

          const SizedBox(height: 25),

          if (!_googleLinked) ...[
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
              'Waffer 2.3.0',

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

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;
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
    this.photoUrl,
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
          CircleAvatar(
            radius: 27,

            backgroundColor: accent.withValues(alpha: 0.15),

            backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                ? NetworkImage(photoUrl!)
                : null,

            child: photoUrl == null || photoUrl!.isEmpty
                ? Icon(
                    placeholder
                        ? Icons.person_off_outlined
                        : Icons.person_outline_rounded,
                    color: accent,
                    size: 30,
                  )
                : null,
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 10),

      child: Text(
        title,

        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

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
    return Material(
      color: surface,

      borderRadius: BorderRadius.circular(20),

      child: InkWell(
        borderRadius: BorderRadius.circular(20),

        onTap: onTap,

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),

          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,

                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),

                  borderRadius: BorderRadius.circular(14),
                ),

                child: Icon(icon, color: accent, size: 22),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,

                      style: TextStyle(
                        color: textPrimary,

                        fontSize: 15,

                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,

                      style: TextStyle(color: textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),

              trailing ??
                  Icon(
                    Icons.arrow_back_ios_new_rounded,

                    color: textSecondary.withValues(alpha: 0.5),

                    size: 16,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditIncomeDialog extends StatefulWidget {
  final String title;
  final double initialAmount;
  final Color accent;

  const _EditIncomeDialog({
    required this.title,
    required this.initialAmount,
    required this.accent,
  });

  @override
  State<_EditIncomeDialog> createState() => _EditIncomeDialogState();
}

class _EditIncomeDialogState extends State<_EditIncomeDialog> {
  static const double _maxAmount = 999999999;

  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialAmount > 0 && widget.initialAmount.isFinite
          ? formatMoney(widget.initialAmount)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = parseAmount(_controller.text);
    if (!amount.isFinite || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً أكبر من صفر');
      return;
    }
    if (amount > _maxAmount) {
      setState(() => _error = 'المبلغ أكبر من الحد المسموح');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [ThousandsInputFormatter()],
        textAlign: TextAlign.center,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'المبلغ',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('حفظ', style: TextStyle(color: widget.accent)),
        ),
      ],
    );
  }
}
