import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/notification_service.dart';
import 'package:waffer/core/data/transaction_store.dart';
import 'package:waffer/core/theme/app_color.dart';

class SettingsScreen extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final VoidCallback onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.themeNotifier,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState
    extends State<SettingsScreen> {
  bool _appLock = false;

  String _language = 'العربية';

  String _userName = '';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();

    widget.themeNotifier.addListener(
      _onThemeChanged,
    );

    _loadSettings();
  }

  @override
  void dispose() {
    widget.themeNotifier.removeListener(
      _onThemeChanged,
    );

    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    final prefs =
        await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _appLock =
          prefs.getBool('app_lock') ?? false;

      _language =
          prefs.getString('language') ??
              'العربية';

      _userName =
          prefs.getString('user_name') ?? '';

      _userEmail =
          prefs.getString('user_email') ?? '';
    });
  }

  Future<void> _toggleAppLock(
      bool value) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      'app_lock',
      value,
    );

    if (!mounted) return;

    setState(() {
      _appLock = value;
    });
  }

  Future<void> _selectLanguage() async {
    final selected =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,

      builder: (context) {
        final isDark =
            Theme.of(context).brightness ==
                Brightness.dark;

        final surface = isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface;

        final textPrimary = isDark
            ? AppColors.darkTextPrimary
            : AppColors.lightTextPrimary;

        final accent = isDark
            ? AppColors.darkAccent
            : AppColors.lightAccent;

        return Container(
          decoration: BoxDecoration(
            color: surface,

            borderRadius:
                const BorderRadius.vertical(
              top: Radius.circular(30),
            ),
          ),

          padding:
              const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [

              Container(
                width: 45,
                height: 5,

                decoration: BoxDecoration(
                  color:
                      textPrimary.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 25),

              Text(
                'اللغة',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight:
                      FontWeight.bold,
                  color: textPrimary,
                  fontFamily: 'Cairo',
                ),
              ),

              const SizedBox(height: 20),

              _LanguageOption(
                title: 'العربية',
                selected:
                    _language == 'العربية',
                accent: accent,
                textColor: textPrimary,
                onTap: () =>
                    Navigator.pop(
                  context,
                  'العربية',
                ),
              ),

              const SizedBox(height: 12),

              _LanguageOption(
                title: 'English',
                selected:
                    _language == 'English',
                accent: accent,
                textColor: textPrimary,
                onTap: () =>
                    Navigator.pop(
                  context,
                  'English',
                ),
              ),

              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );

    if (selected == null) return;

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      'language',
      selected,
    );

    if (!mounted) return;

    setState(() {
      _language = selected;
    });
  }

  void _showAbout() {
    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final surface = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    showDialog(
      context: context,

      builder: (context) {
        return AlertDialog(
          backgroundColor: surface,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(25),
          ),

          title: Text(
            'عن وفر',
            textAlign: TextAlign.center,

            style: TextStyle(
              color: textPrimary,
              fontWeight:
                  FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),

          content: Column(
            mainAxisSize:
                MainAxisSize.min,

            children: [

              Text(
                'وفر',

                style: TextStyle(
                  fontSize: 32,
                  fontWeight:
                      FontWeight.bold,
                  color: accent,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'تطبيق بسيط لمساعدتك على إدارة مصاريفك ومتابعة رصيدك.',

                textAlign:
                    TextAlign.center,

                style: TextStyle(
                  color:
                      textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 15),

              Text(
                'الإصدار 1.0.0',

                style: TextStyle(
                  color:
                      textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          actions: [

            TextButton(
              onPressed: () =>
                  Navigator.pop(context),

              child: Text(
                'إغلاق',
                style: TextStyle(
                  color: accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetApp() async {
    final confirm =
        await showDialog<bool>(
      context: context,

      builder: (context) {
        final isDark =
            Theme.of(context).brightness ==
                Brightness.dark;

        return AlertDialog(
          title:
              const Text(
            'إعادة ضبط التطبيق',
          ),

          content:
              const Text(
            'سيتم حذف بيانات المستخدم والرصيد وسجل المصاريف. هل أنت متأكد؟',
          ),

          actions: [

            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),

              child:
                  const Text('إلغاء'),
            ),

            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),

              child: Text(
                'حذف البيانات',

                style: TextStyle(
                  color: isDark
                      ? AppColors.darkAccent
                      : AppColors.lightAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final prefs =
        await SharedPreferences.getInstance();

    await prefs.clear();

    TransactionStore.instance.resetCache();
    NotificationService.instance.resetCache();

    if (!mounted) return;

    Navigator.of(context)
        .popUntil(
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.themeNotifier.value ==
            ThemeMode.dark;

    final bg = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;

    final surface = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,

      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,

        title: Text(
          'الإعدادات',

          style: TextStyle(
            color: textPrimary,
            fontWeight:
                FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),

        leading: IconButton(
          icon: Icon(
            Icons.arrow_forward_ios_rounded,
            color: textPrimary,
          ),

          onPressed: () =>
              Navigator.pop(context),
        ),
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(20),

        children: [

          if (_userName.isNotEmpty ||
              _userEmail.isNotEmpty)
            _ProfileCard(
              name: _userName,
              email: _userEmail,
              accent: accent,
              surface: surface,
              textPrimary:
                  textPrimary,
              textSecondary:
                  textSecondary,
            ),

          const SizedBox(height: 25),

          _SectionTitle(
            title: 'الحساب',
            color: textSecondary,
          ),

          _SettingsTile(
            icon:
                Icons.person_outline_rounded,

            title: 'المعلومات الشخصية',

            subtitle:
                'الاسم والبريد الإلكتروني',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            onTap: () {},
          ),

          const SizedBox(height: 12),

          _SectionTitle(
            title: 'المظهر',
            color: textSecondary,
          ),

          _SettingsTile(
            icon:
                Icons.dark_mode_outlined,

            title: 'الوضع الداكن',

            subtitle: isDark
                ? 'مفعل'
                : 'غير مفعل',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

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
            icon:
                Icons.language_rounded,

            title: 'اللغة',

            subtitle: _language,

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            onTap: _selectLanguage,
          ),

          const SizedBox(height: 25),

          _SectionTitle(
            title: 'الحماية والخصوصية',
            color: textSecondary,
          ),

          _SettingsTile(
            icon:
                Icons.lock_outline_rounded,

            title: 'قفل التطبيق',

            subtitle:
                'استخدام حماية الجهاز عند فتح وفر',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            trailing: Switch(
              value: _appLock,
              activeThumbColor: accent,

              onChanged:
                  _toggleAppLock,
            ),

            onTap: () =>
                _toggleAppLock(
              !_appLock,
            ),
          ),

          const SizedBox(height: 12),

          _SettingsTile(
            icon:
                Icons.privacy_tip_outlined,

            title:
                'الخصوصية والبيانات',

            subtitle:
                'إدارة بياناتك داخل التطبيق',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            onTap: () {},
          ),

          const SizedBox(height: 25),

          _SectionTitle(
            title: 'حول التطبيق',
            color: textSecondary,
          ),

          _SettingsTile(
            icon:
                Icons.info_outline_rounded,

            title: 'عن وفر',

            subtitle:
                'معلومات عن التطبيق',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            onTap: _showAbout,
          ),

          const SizedBox(height: 25),

          _SectionTitle(
            title: 'البيانات',
            color: textSecondary,
          ),

          _SettingsTile(
            icon:
                Icons.delete_outline_rounded,

            title:
                'إعادة ضبط التطبيق',

            subtitle:
                'حذف جميع البيانات والبدء من جديد',

            accent: accent,
            surface: surface,

            textPrimary:
                textPrimary,

            textSecondary:
                textSecondary,

            onTap: _resetApp,
          ),

          const SizedBox(height: 30),

          Center(
            child: Text(
              'Waffer • 1.0.0',

              style: TextStyle(
                color:
                    textSecondary
                        .withValues(alpha: 0.6),

                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ProfileCard
    extends StatelessWidget {
  final String name;
  final String email;

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
  });

  @override
  Widget build(
      BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: surface,

        borderRadius:
            BorderRadius.circular(25),
      ),

      child: Row(
        children: [

          CircleAvatar(
            radius: 27,

            backgroundColor:
                accent.withValues(alpha: 0.15),

            child: Icon(
              Icons.person_outline_rounded,

              color: accent,
              size: 30,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Text(
                  name.isEmpty
                      ? 'المستخدم'
                      : name,

                  style: TextStyle(
                    color:
                        textPrimary,

                    fontSize: 17,

                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                if (email.isNotEmpty)
                  Text(
                    email,

                    textDirection:
                        TextDirection.ltr,

                    style: TextStyle(
                      color:
                          textSecondary,

                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.color,
  });

  @override
  Widget build(
      BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(
        right: 5,
        bottom: 10,
      ),

      child: Text(
        title,

        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }
}

class _SettingsTile
    extends StatelessWidget {
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
  Widget build(
      BuildContext context) {
    return Material(
      color: surface,

      borderRadius:
          BorderRadius.circular(20),

      child: InkWell(
        borderRadius:
            BorderRadius.circular(20),

        onTap: onTap,

        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),

          child: Row(
            children: [

              Container(
                width: 43,
                height: 43,

                decoration:
                    BoxDecoration(
                  color:
                      accent.withValues(
                    alpha: 0.12,
                  ),

                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),

                child: Icon(
                  icon,

                  color: accent,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      title,

                      style: TextStyle(
                        color:
                            textPrimary,

                        fontSize: 15,

                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,

                      style: TextStyle(
                        color:
                            textSecondary,

                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              trailing ??
                  Icon(
                    Icons
                        .arrow_back_ios_new_rounded,

                    color:
                        textSecondary
                            .withValues(alpha: 0.5),

                    size: 16,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOption
    extends StatelessWidget {
  final String title;
  final bool selected;

  final Color accent;
  final Color textColor;

  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.selected,
    required this.accent,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(
      BuildContext context) {
    return GestureDetector(
      onTap: onTap,

      child: AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 200,
        ),

        width: double.infinity,

        padding:
            const EdgeInsets.all(16),

        decoration:
            BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.transparent,

          borderRadius:
              BorderRadius.circular(16),

          border: Border.all(
            color: selected
                ? accent
                : textColor.withValues(
                    alpha: 0.1,
                  ),
          ),
        ),

        child: Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,

          children: [

            Text(
              title,

              style: TextStyle(
                color: textColor,
                fontWeight:
                    FontWeight.w600,
              ),
            ),

            if (selected)
              Icon(
                Icons
                    .check_circle_rounded,

                color: accent,
              ),
          ],
        ),
      ),
    );
  }
}
