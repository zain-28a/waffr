import 'package:flutter/material.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/widgets/brand/waffer_w_mark.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

/// أول شاشة في التشغيل الأول.
///
/// ربط حساب Google اختياري تماماً: وضع الضيف يعمل بكامل
/// الميزات محلياً كما كان التطبيق يعمل دائماً.
class LoginScreen extends StatefulWidget {
  /// يُستدعى بعد اختيار المستخدم، سواء بحساب أو كضيف.
  final Future<void> Function() onCompleted;

  const LoginScreen({super.key, required this.onCompleted});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _signInWithGoogle() async {
    if (_busy) return;

    setState(() => _busy = true);

    final result = await BackupService.instance.signInAndRestore();

    if (!mounted) return;

    if (result == GoogleLinkResult.failed) {
      setState(() => _busy = false);

      showAppSnackBar(
        context,
        'لم يتم تسجيل الدخول. يمكنك المحاولة مجدداً أو المتابعة كضيف.',
      );

      return;
    }

    await widget.onCompleted();
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;

    setState(() => _busy = true);

    await BackupService.instance.continueAsGuest();

    if (!mounted) return;

    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              Center(
                child: WafferWMark(size: 72, color: accent),
              ),

              const SizedBox(height: 28),

              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'مرحباً بك في '),
                    TextSpan(
                      text: 'وفّر',
                      style: TextStyle(color: accent),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Tajawal',
                ),
              ),

              const SizedBox(height: 10),

              Text(
                'سجّل الدخول لحفظ بياناتك واستعادتها عند إعادة التثبيت',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 16),
              ),

              const SizedBox(height: 56),

              GlassContainer(
                colorType: GlassColorType.surface,
                borderRadius: 28,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.cloud_done_outlined,
                      text: 'نسخة احتياطية تلقائية في حسابك على Google Drive',
                      accent: accent,
                      textPrimary: textPrimary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 56),

              GlassButton(
                onTap: _signInWithGoogle,
                colorType: GlassColorType.accent,
                borderRadius: 22,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 10,
                ),
                child: _busy
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: accent,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.login_rounded,
                            size: 20,
                            color: Color.fromARGB(255, 255, 255, 255),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'المتابعة باستخدام Google',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: Color.fromARGB(255, 255, 255, 255),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 14),

              TextButton(
                onPressed: _busy ? null : _continueAsGuest,
                child: Text(
                  'المتابعة كضيف',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accent;
  final Color textPrimary;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.accent,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
