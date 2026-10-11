// Signed-in profile: name and sign-out.

import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/data/services/backup_service.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/widgets/brand/profile_avatar.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/screens/offline/settings/change_password_screen.dart';

// Edit display name, or sign out of the synced account.
class AccountScreen extends StatefulWidget {
  final Future<void> Function()? onSignedOut;

  const AccountScreen({super.key, this.onSignedOut});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _nameController = TextEditingController();

  String _email = '';
  bool _busy = false;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final email = await AuthSession.instance.email() ?? '';

    if (!mounted) return;

    setState(() {
      _email = email;
      _nameController.text = prefs.getString('user_name') ?? '';
    });
  }

  // Writes the display name through BackupService and shows a snackbar.
  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _savingName) return;

    setState(() => _savingName = true);
    await BackupService.instance.updateDisplayName(name);
    if (!mounted) return;
    setState(() => _savingName = false);
    showAppSnackBar(context, 'تم حفظ الاسم', success: true);
  }

  // Confirms, clears the session, then runs the host's onSignedOut callback.
  Future<void> _signOut() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'تسجيل الخروج',
      message:
          'سيتم تسجيل الخروج من حسابك على هذا الجهاز. تبقى بياناتك محفوظة هنا، وتعود إلى شاشة الدخول حيث يمكنك المتابعة كضيف أو تسجيل الدخول بحساب آخر.',
      confirmLabel: 'تسجيل الخروج',
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    final signedOut = widget.onSignedOut;
    if (signedOut != null) {
      await signedOut();
    } else {
      await AuthSession.instance.clearSession();
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _deleteAccount() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'حذف الحساب',
      message:
          'سيتم حذف حسابك وكل بياناته من الخادم ومن هذا الجهاز ومن النسخة الاحتياطية إن وُجدت. لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف الحساب',
      destructive: true,
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    // Server first: if it fails, local data stays so the user can retry.
    final remote = await AuthSession.instance.deleteRemoteAccount();
    if (!remote.ok) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnackBar(context, remote.message);
      return;
    }
    await BackupService.instance.deleteAccount();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      appBar: WaffrBackHeader(
        title: 'الحساب',
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: staggered([
          Center(
            child: ProfileAvatar(
              accent: accent,
              radius: 42,
              signedIn: true,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'الاسم',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textAlign: TextAlign.right,
            style: TextStyle(color: textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'الاسم المعروض',
              hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _savingName ? null : _saveName,
              child: Text(
                _savingName ? 'جارٍ الحفظ...' : 'حفظ الاسم',
                style: TextStyle(color: accent, fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal']),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'البريد الإلكتروني',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _email.isEmpty ? '—' : _email,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: textSecondary, fontSize: 15),
            ),
          ),
          const SizedBox(height: 25),
          _ActionTile(
            icon: Icons.lock_reset_rounded,
            title: 'تغيير كلمة المرور',
            subtitle: 'يسجّل الخروج من أجهزتك الأخرى',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            busy: _busy,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.logout_rounded,
            title: 'تسجيل الخروج',
            subtitle: 'العودة إلى شاشة الدخول، والبيانات تبقى على الجهاز',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            busy: _busy,
            onTap: _signOut,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.delete_forever_outlined,
            title: 'حذف الحساب',
            subtitle: 'حذف الحساب وبياناته من الخادم والجهاز',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            busy: _busy,
            onTap: _deleteAccount,
          ),
        ]),
      ),
    );
  }
}

// Icon + label row used for account actions.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final bool busy;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      busy: busy,
      onTap: onTap,
    );
  }
}
