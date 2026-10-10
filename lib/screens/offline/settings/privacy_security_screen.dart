// Privacy hub: account data, cloud sync, app lock, and local reset detail pages.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffer/widgets/containers/app_list_tile.dart';
import 'package:waffer/widgets/button/app_primary_button.dart';
import 'package:waffer/data/services/local_data_reset.dart';
import 'package:waffer/core/security/app_lock.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

// Entry list that opens deeper privacy/security detail pages.
class PrivacySecurityScreen extends StatefulWidget {
  final dynamic appFlowController;

  const PrivacySecurityScreen({
    super.key,
    this.appFlowController,
  });

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final ValueNotifier<bool> _headerElevated = ValueNotifier(false);

  bool _loggedIn = false;
  bool _appLock = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _headerElevated.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loggedIn = await AuthSession.instance.isLoggedIn();
    final appLock = await AppLock.isEnabled();

    if (!mounted) return;

    setState(() {
      _loggedIn = loggedIn;
      _appLock = appLock;
      _loading = false;
    });
  }

  Future<void> _openDetail(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            WafferBackHeader(
              applySafeArea: false,
              elevated: _headerElevated,
              title: 'الخصوصية والأمان',
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: colors.accent),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth != 0) return false;
                        final next = notification.metrics.pixels > 6;
                        if (_headerElevated.value != next) {
                          _headerElevated.value = next;
                        }
                        return false;
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        children: [
                          _SectionLabel(
                            title: 'بياناتك',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.badge_outlined,
                                title: 'بيانات الحساب',
                                colors: colors,
                                onTap: () => _openDetail(
                                  const _AccountDataDetailPage(),
                                ),
                              ),
                              _SettingsRow(
                                icon: Icons.cloud_sync_outlined,
                                title: 'المزامنة السحابية',
                                colors: colors,
                                status: _loggedIn ? 'مفعّلة' : 'وضع الضيف',
                                statusEmphasis: _loggedIn,
                                onTap: () => _openDetail(
                                  _CloudSyncDetailPage(loggedIn: _loggedIn),
                                ),
                              ),
                              _SettingsRow(
                                icon: Icons.sync_alt_rounded,
                                title: 'البيانات المتزامنة',
                                colors: colors,
                                showDivider: false,
                                onTap: () => _openDetail(
                                  const _SyncedDataDetailPage(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(
                            title: 'حماية التطبيق',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.lock_outline_rounded,
                                title: 'قفل التطبيق',
                                colors: colors,
                                status: _appLock ? 'مفعّل' : 'غير مفعّل',
                                statusEmphasis: _appLock,
                                showDivider: false,
                                onTap: () => _openDetail(
                                  _AppLockDetailPage(
                                    appFlowController: widget.appFlowController,
                                    auth: _auth,
                                    initiallyEnabled: _appLock,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(
                            title: 'البيانات والحساب',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.delete_outline_rounded,
                                title: 'إعادة ضبط البيانات المحلية',
                                colors: colors,
                                showDivider: false,
                                onTap: () => _openDetail(
                                  const _LocalResetDetailPage(),
                                ),
                              ),
                            ],
                          ),
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

// Explains what account fields are stored and how financial data stays private.
class _AccountDataDetailPage extends StatelessWidget {
  const _AccountDataDetailPage();

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return _PrivacyDetailScaffold(
      title: 'بيانات الحساب',
      colors: colors,
      children: [
        _DetailLead(
          icon: Icons.badge_outlined,
          colors: colors,
          text:
              'يحتفظ وفّر بمعلومات أساسية لتشغيل الحساب وعرض الملف الشخصي.',
        ),
        const SizedBox(height: 16),
        _InfoGroup(
          colors: colors,
          children: const [
            _InfoLine(label: 'الاسم المعروض'),
            _InfoLine(label: 'البريد الإلكتروني'),
            _InfoLine(label: 'الجنس، إن تم إدخاله'),
            _InfoLine(label: 'تاريخ الميلاد'),
            _InfoLine(
              label: 'صورة الملف الشخصي على هذا الجهاز',
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _NoteText(
          colors: colors,
          text:
              'عند تسجيل الدخول، تُزامَن معلومات الملف الشخصي ذات الصلة مع الحساب. صورة الملف الشخصي تبقى محفوظة محلياً على الجهاز.',
        ),
      ],
    );
  }
}

// Cloud sync status and how backups relate to a signed-in account.
class _CloudSyncDetailPage extends StatelessWidget {
  final bool loggedIn;

  const _CloudSyncDetailPage({required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return _PrivacyDetailScaffold(
      title: 'المزامنة السحابية',
      colors: colors,
      children: [
        _StatusBanner(
          colors: colors,
          emphasized: loggedIn,
          title: loggedIn ? 'مفعّلة' : 'غير متاحة في وضع الضيف',
          subtitle: loggedIn
              ? 'مرتبطة بالحساب الذي سجّلت الدخول إليه.'
              : 'لا تتم مزامنة سحابية أثناء استخدام التطبيق كضيف.',
        ),
        const SizedBox(height: 16),
        _InfoGroup(
          colors: colors,
          children: loggedIn
              ? const [
                  _InfoLine(
                    label:
                        'تُحفظ بياناتك على الجهاز أولاً، فيعمل التطبيق دون اتصال.',
                  ),
                  _InfoLine(
                    label:
                        'عند توفر الاتصال، تُزامَن تلقائياً مع خوادم وفّر.',
                  ),
                  _InfoLine(
                    label:
                        'بيانات كل حساب منفصلة عن غيره، ولا يصل إليها إلا صاحبها.',
                    showDivider: false,
                  ),
                ]
              : const [
                  _InfoLine(
                    label: 'تبقى بياناتك محفوظة على هذا الجهاز.',
                  ),
                  _InfoLine(
                    label:
                        'لا تُرسل البيانات إلى السحابة في وضع الضيف.',
                  ),
                  _InfoLine(
                    label:
                        'بعد تسجيل الدخول، تُزامَن بياناتك تلقائياً عند توفر الاتصال.',
                    showDivider: false,
                  ),
                ],
        ),
      ],
    );
  }
}

// Lists which local datasets participate in sync.
class _SyncedDataDetailPage extends StatelessWidget {
  const _SyncedDataDetailPage();

  static const _synced = <String>[
    'المعاملات المالية',
    'أهداف التوفير والتحويلات',
    'الالتزامات (المصروفات المتكررة)',
    'قوائم التسوق وعناصرها',
    'الإشعارات',
    'التصنيفات المخصصة',
    'إعدادات المستخدم',
    'معلومات الملف الشخصي ذات الصلة',
  ];

  static const _localOnly = <String>[
    'إعدادات قفل التطبيق',
    'بيانات تسجيل الدخول',
    'ملفات صور الملف الشخصي المحلية',
    'بيانات خاصة بالجهاز',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return _PrivacyDetailScaffold(
      title: 'البيانات المتزامنة',
      colors: colors,
      children: [
        _NoteText(
          colors: colors,
          text:
              'تُزامَن البيانات التالية مع الحساب عند تسجيل الدخول وتوفر الاتصال.',
        ),
        const SizedBox(height: 16),
        _SectionLabel(title: 'تُزامَن مع الحساب', color: colors.textSecondary),
        _InfoGroup(
          colors: colors,
          children: [
            for (var i = 0; i < _synced.length; i++)
              _InfoLine(
                label: _synced[i],
                showDivider: i != _synced.length - 1,
              ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionLabel(title: 'تبقى على الجهاز', color: colors.textSecondary),
        _InfoGroup(
          colors: colors,
          children: [
            for (var i = 0; i < _localOnly.length; i++)
              _InfoLine(
                label: _localOnly[i],
                showDivider: i != _localOnly.length - 1,
              ),
          ],
        ),
      ],
    );
  }
}

// Toggle device app lock with biometric/passcode confirmation.
class _AppLockDetailPage extends StatefulWidget {
  final dynamic appFlowController;
  final LocalAuthentication auth;
  final bool initiallyEnabled;

  const _AppLockDetailPage({
    required this.appFlowController,
    required this.auth,
    required this.initiallyEnabled,
  });

  @override
  State<_AppLockDetailPage> createState() => _AppLockDetailPageState();
}

class _AppLockDetailPageState extends State<_AppLockDetailPage> {
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initiallyEnabled;
  }

  // Enables after device auth; disables by clearing AppLock prefs.
  Future<void> _toggle(bool value) async {
    if (_busy) return;

    setState(() => _busy = true);

    final result = await AppLock.setEnabled(
      enabled: value,
      auth: widget.auth,
      onEnabled: () {
        widget.appFlowController?.refreshAppLockState(
          sessionAuthenticated: true,
        );
      },
      onDisabled: () {
        widget.appFlowController?.refreshAppLockState();
      },
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      if (result == AppLockToggleResult.enabled) {
        _enabled = true;
      } else if (result == AppLockToggleResult.disabled) {
        _enabled = false;
      }
    });

    switch (result) {
      case AppLockToggleResult.enabled:
        showAppSnackBar(context, 'تم تفعيل قفل التطبيق', success: true);
      case AppLockToggleResult.disabled:
        showAppSnackBar(context, 'تم إيقاف قفل التطبيق', success: true);
      case AppLockToggleResult.unsupported:
        showAppSnackBar(
          context,
          'جهازك لا يدعم البصمة أو قفل الشاشة',
          kind: AppFeedbackKind.warning,
        );
      case AppLockToggleResult.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return _PrivacyDetailScaffold(
      title: 'قفل التطبيق',
      colors: colors,
      children: [
        _StatusBanner(
          colors: colors,
          emphasized: _enabled,
          title: _enabled ? 'مفعّل' : 'غير مفعّل',
          subtitle: 'يحمي الوصول إلى وفّر على هذا الجهاز.',
        ),
        const SizedBox(height: 16),
        _InfoGroup(
          colors: colors,
          children: const [
            _InfoLine(
              label:
                  'يستخدم قفل التطبيق مصادقة الجهاز، مثل البصمة أو التعرف على الوجه أو رمز الجهاز.',
            ),
            _InfoLine(
              label:
                  'يمنع فتح التطبيق على هذا الجهاز دون تأكيد هويتك.',
            ),
            _InfoLine(
              label: 'هذا الإعداد يبقى على الجهاز ولا يُزامَن مع الحساب.',
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          surface: colors.surface,
          children: [
            _SettingsRow(
              icon: Icons.lock_outline_rounded,
              title: 'قفل التطبيق',
              colors: colors,
              showDivider: false,
              showChevron: false,
              trailing: Switch(
                value: _enabled,
                activeThumbColor: colors.accent,
                onChanged: _busy ? null : _toggle,
              ),
              onTap: _busy ? null : () => _toggle(!_enabled),
            ),
          ],
        ),
      ],
    );
  }
}

// Wipe local app data while keeping the user on a clean slate.
class _LocalResetDetailPage extends StatelessWidget {
  const _LocalResetDetailPage();

  Future<void> _confirmReset(BuildContext context) async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'إعادة ضبط البيانات المحلية',
      message:
          'سيتم حذف البيانات المخزّنة على هذا الجهاز. لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف البيانات',
      destructive: true,
    );

    if (confirm != true || !context.mounted) return;

    await LocalDataReset.resetCurrentDevice();
    if (!context.mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return _PrivacyDetailScaffold(
      title: 'إعادة ضبط البيانات المحلية',
      colors: colors,
      children: [
        _DetailLead(
          icon: Icons.delete_outline_rounded,
          colors: colors,
          text: 'يؤثر هذا الإجراء على البيانات المخزّنة على الجهاز الحالي فقط.',
        ),
        const SizedBox(height: 16),
        _InfoGroup(
          colors: colors,
          children: const [
            _InfoLine(
              label:
                  'سيتم حذف البيانات المالية المحلية وإعدادات هذا الجهاز.',
            ),
            _InfoLine(
              label: 'لا يمكن التراجع عن هذا الإجراء بعد تأكيده.',
            ),
            _InfoLine(
              label:
                  'لا يحذف هذا الإجراء حسابك من الخادم. لحذف الحساب استخدم شاشة الحساب بعد تسجيل الدخول.',
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 22),
        AppPrimaryButton(
          label: 'إعادة ضبط هذا الجهاز',
          onTap: () => _confirmReset(context),
        ),
      ],
    );
  }
}

// Shared scaffold for privacy detail pages (header + scroll body).
class _PrivacyDetailScaffold extends StatelessWidget {
  final String title;
  final _PrivacyColors colors;
  final List<Widget> children;

  const _PrivacyDetailScaffold({
    required this.title,
    required this.colors,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.background,
      appBar: WafferBackHeader(
        title: title,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: children,
      ),
    );
  }
}

// Light/dark color snapshot for privacy screens.
class _PrivacyColors {
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;

  const _PrivacyColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
  });

  factory _PrivacyColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _PrivacyColors(
      background: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      textPrimary:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      textSecondary:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
    );
  }
}

// Section heading above a settings group.
class _SectionLabel extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionLabel({required this.title, required this.color});

  @override
  Widget build(BuildContext context) => AppSectionTitle(title: title);
}

// Card wrapping one or more privacy settings rows.
// Rows stacked like the Settings screen: one card per row.
class _SettingsGroup extends StatelessWidget {
  final Color surface;
  final List<Widget> children;

  const _SettingsGroup({
    required this.surface,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

// Tappable privacy settings row with optional trailing widget.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final _PrivacyColors colors;
  final String? status;
  final bool statusEmphasis;
  final bool showDivider;
  final bool showChevron;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.colors,
    this.status,
    this.statusEmphasis = false,
    this.showDivider = true,
    this.showChevron = true,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: icon,
      title: title,
      status: status,
      statusOn: statusEmphasis,
      trailing: trailing,
      showChevron: showChevron,
      onTap: onTap,
    );
  }
}

// Small pill showing on/off or similar status text.
// Banner summarizing the current privacy/security status.
class _StatusBanner extends StatelessWidget {
  final _PrivacyColors colors;
  final bool emphasized;
  final String title;
  final String subtitle;

  const _StatusBanner({
    required this.colors,
    required this.emphasized,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasized ? colors.accent : colors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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

// Intro icon + title block at the top of a detail page.
class _DetailLead extends StatelessWidget {
  final IconData icon;
  final _PrivacyColors colors;
  final String text;

  const _DetailLead({
    required this.icon,
    required this.colors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: colors.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w600,
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Grouped list of informational lines.
class _InfoGroup extends StatelessWidget {
  final _PrivacyColors colors;
  final List<Widget> children;

  const _InfoGroup({
    required this.colors,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

// Single bullet-style info line inside an _InfoGroup.
class _InfoLine extends StatelessWidget {
  final String label;
  final bool showDivider;

  const _InfoLine({
    required this.label,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    height: 1.45,
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 44,
            color: colors.textSecondary.withValues(alpha: 0.12),
          ),
      ],
    );
  }
}

// Muted footnote under a detail section.
class _NoteText extends StatelessWidget {
  final _PrivacyColors colors;
  final String text;

  const _NoteText({
    required this.colors,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: 13.5,
        height: 1.55,
        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
      ),
    );
  }
}
