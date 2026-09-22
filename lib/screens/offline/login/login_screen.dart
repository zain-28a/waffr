import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waffer/core/data/backup_service.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/screens/offline/login/account_creation_flow.dart';
import 'package:waffer/screens/offline/login/auth_fields.dart';
import 'package:waffer/widgets/brand/waffer_logo.dart';
import 'package:waffer/widgets/button/glass_button.dart';
import 'package:waffer/widgets/containers/glass.dart';

/// شاشة الدخول: بريد وكلمة مرور، أو المتابعة كضيف محلياً.
class LoginScreen extends StatefulWidget {
  final Future<void> Function() onCompleted;
  final bool allowGuest;
  final bool popOnSuccess;

  const LoginScreen({
    super.key,
    required this.onCompleted,
    this.allowGuest = true,
    this.popOnSuccess = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final email = _emailController.text.trim();
    return email.contains('@') &&
        email.contains('.') &&
        _passwordController.text.isNotEmpty &&
        !_busy;
  }

  Future<void> _login() async {
    if (!_canSubmit) return;

    setState(() => _busy = true);

    final result = await AuthSession.instance.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _busy = false);
      showAppSnackBar(context, result.message);
      return;
    }

    await SyncService.instance.syncNow();
    if (!mounted) return;
    // تسجيل الدخول لا يعيد شاشة اختيار المظهر. يُستخدم المظهر المحفوظ.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('first_launch') ?? true) {
      await prefs.setBool('first_launch', false);
    }
    if (!mounted) return;
    await _finish();
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;

    setState(() => _busy = true);
    await BackupService.instance.continueAsGuest();
    if (!mounted) return;
    await _finish();
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountCreationFlow(
          onCompleted: widget.onCompleted,
          popOnSuccess: widget.popOnSuccess,
        ),
      ),
    );
  }

  Future<void> _finish() async {
    await widget.onCompleted();
    if (widget.popOnSuccess && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Image.asset('assets/brand/waffer_logo.png', width: 150, height: 150),
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
                'سجّل الدخول لمزامنة بياناتك بين أجهزتك',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 40),
              GlassContainer(
                colorType: GlassColorType.surface,
                borderRadius: 28,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthFieldLabel(text: 'البريد الإلكتروني', color: textPrimary),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: textPrimary, fontSize: 16),
                      decoration: authFieldDecoration(
                        hint: 'example@email.com',
                        fillColor: surface,
                        textSecondary: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthFieldLabel(text: 'كلمة المرور', color: textPrimary),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: textPrimary, fontSize: 16),
                      decoration: authFieldDecoration(
                        hint: '••••••••',
                        fillColor: surface,
                        textSecondary: textSecondary,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              GlassButton(
                onTap: _canSubmit ? _login : () {},
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
                            color: Color.fromARGB(255, 255, 255, 255),
                          ),
                        ),
                      )
                    : Text(
                        'تسجيل الدخول',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _openRegister,
                child: Text(
                  'إنشاء حساب جديد',
                  style: TextStyle(
                    color: accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
              if (widget.allowGuest)
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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
