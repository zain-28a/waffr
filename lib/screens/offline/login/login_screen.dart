import 'package:flutter/material.dart';
import 'package:waffer/widgets/button/app_primary_button.dart';
import 'package:waffer/data/services/backup_service.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/sync/sync_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/screens/offline/login/account_creation_flow.dart';
import 'package:waffer/screens/offline/login/auth_fields.dart';
import 'package:waffer/screens/offline/login/forgot_password_screen.dart';
import 'package:waffer/widgets/brand/waffer_logo.dart';
import 'package:waffer/widgets/containers/glass.dart';
import 'package:waffer/core/prefs/app_prefs.dart';

// Sign-in with email/password, register, or continue as a local guest.

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
  // Shown above the main button; cleared as soon as a field changes.
  String? _message;
  AppFeedbackKind _messageKind = AppFeedbackKind.error;
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

  // Auth, sync, then clear first-launch so theme select is not shown again.
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
      _show(result.message);
      return;
    }

    await SyncService.instance.syncNow();
    if (!mounted) return;
    final prefs = await AppPrefs.instance;
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

  // After a reset, sign in with the new password straight away.
  Future<void> _openForgotPassword() async {
    final result = await Navigator.of(context)
        .push<({String email, String password})>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    _emailController.text = result.email;
    _passwordController.text = result.password;
    setState(() {});
    await _login();
  }

  Future<void> _finish() async {
    await widget.onCompleted();
    if (widget.popOnSuccess && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _show(String? message, {bool success = false}) {
    setState(() {
      _message = message;
      _messageKind = success ? AppFeedbackKind.success : AppFeedbackKind.error;
    });
  }

  bool get _emailValid {
    final email = _emailController.text.trim();
    return email.contains('@') && email.contains('.');
  }

  // Why the main button is disabled, in plain words.
  String? get _missingReason {
    if (!_emailValid) return 'أدخل بريداً إلكترونياً صالحاً';
    if (_passwordController.text.isEmpty) return 'أدخل كلمة المرور';
    return null;
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
              const SizedBox(height: 20),
              const Center(child: WafferLogo(size: 72)),
              const SizedBox(height: 16),
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
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'سجّل الدخول لمزامنة بياناتك بين أجهزتك',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 16),
              ),
              const SizedBox(height: 32),
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
                      onChanged: (_) => setState(() => _message = null),
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
                      onChanged: (_) => setState(() => _message = null),
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _busy ? null : _openForgotPassword,
                  child: Text(
                    'نسيت كلمة المرور؟',
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppInlineMessage(message: _message, kind: _messageKind),
              AppPrimaryButton(
                label: 'تسجيل الدخول',
                enabled: _canSubmit,
                onDisabledTap: () => _show(_missingReason),
                busy: _busy,
                onTap: _login,
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
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
