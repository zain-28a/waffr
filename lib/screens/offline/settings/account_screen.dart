import 'package:flutter/material.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _nameController = TextEditingController();

  String _email = '';
  String? _photoUrl;
  List<LinkedGoogleAccount> _accounts = [];
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
    final backup = BackupService.instance;
    final email = await backup.linkedEmail() ?? '';
    final photo = await backup.linkedPhotoUrl();
    final accounts = await backup.linkedAccounts();

    LinkedGoogleAccount? current;
    for (final account in accounts) {
      if (account.email == email) {
        current = account;
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      _email = email;
      _photoUrl = photo ?? current?.photoUrl;
      _accounts = accounts;
      _nameController.text = current?.displayName ?? '';
    });
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _savingName) return;

    setState(() => _savingName = true);
    await BackupService.instance.updateDisplayName(name);
    if (!mounted) return;
    setState(() => _savingName = false);
    showAppSnackBar(context, 'تم حفظ الاسم', success: true);
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('تسجيل الخروج'),
          content: const Text(
            'سيتم فصل الحساب عن هذا الجهاز فقط. بياناتك المحلية والنسخة الاحتياطية في Drive لن تُحذف.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'تسجيل الخروج',
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

    setState(() => _busy = true);
    await BackupService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('حذف الحساب'),
          content: const Text(
            'سيتم حذف بيانات هذا الحساب من الجهاز ومن النسخة الاحتياطية إن وُجدت. لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'حذف الحساب',
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

    setState(() => _busy = true);
    await BackupService.instance.deleteAccount();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _addOrSwitch() async {
    if (_busy) return;

    setState(() => _busy = true);

    final result = await BackupService.instance.addOrSwitchAccount();

    if (!mounted) return;

    if (result == GoogleLinkResult.failed) {
      setState(() => _busy = false);
      showAppSnackBar(
        context,
        'تعذر تبديل الحساب. تحقق من الاتصال وحاول مرة أخرى.',
      );
      return;
    }

    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnackBar(
      context,
      result == GoogleLinkResult.restored
          ? 'تم استعادة بيانات الحساب'
          : 'تم ربط الحساب',
      success: true,
    );
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
      appBar: WafferPageHeader(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'الحساب',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: accent.withValues(alpha: 0.15),
              backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: _photoUrl == null || _photoUrl!.isEmpty
                  ? Icon(Icons.person_outline_rounded, color: accent, size: 34)
                  : null,
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
                style: TextStyle(color: accent, fontFamily: 'Tajawal'),
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
          const SizedBox(height: 6),
          Text(
            'لا يمكن تعديل البريد أو الصورة، فهما من حساب Google.',
            style: TextStyle(color: textSecondary, fontSize: 12, height: 1.4),
          ),
          if (_accounts.length > 1) ...[
            const SizedBox(height: 25),
            Text(
              'تبديل الحساب',
              style: TextStyle(
                color: textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            for (final account in _accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AccountTile(
                  account: account,
                  selected: account.email == _email,
                  surface: surface,
                  accent: accent,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onTap: account.email == _email || _busy ? null : _addOrSwitch,
                ),
              ),
          ],
          const SizedBox(height: 25),
          _ActionTile(
            icon: Icons.person_add_alt_1_outlined,
            title: 'إضافة حساب',
            subtitle: 'ربط حساب Google آخر والتبديل إليه',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            busy: _busy,
            onTap: _addOrSwitch,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.logout_rounded,
            title: 'تسجيل الخروج',
            subtitle: 'البقاء على الجهاز بوضع الضيف',
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
            subtitle: 'حذف بيانات هذا الحساب من الجهاز والنسخة الاحتياطية',
            accent: accent,
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            busy: _busy,
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final LinkedGoogleAccount account;
  final bool selected;
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback? onTap;

  const _AccountTile({
    required this.account,
    required this.selected,
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.12),
                backgroundImage:
                    account.photoUrl != null && account.photoUrl!.isNotEmpty
                    ? NetworkImage(account.photoUrl!)
                    : null,
                child: account.photoUrl == null || account.photoUrl!.isEmpty
                    ? Icon(Icons.person_outline_rounded, color: accent, size: 18)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      account.email,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
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
              busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : Icon(
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
