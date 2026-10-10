import 'package:flutter/material.dart';
import 'package:waffer/widgets/button/app_primary_button.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/screens/offline/login/auth_fields.dart';
import 'package:waffer/widgets/containers/glass.dart';

// Forgot password: email a code, then set a new password with it. Pops with
// the email and new password so the login screen can sign in.

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _busy = false;
  // Shown above the main button; cleared as soon as a field changes.
  String? _message;
  AppFeedbackKind _messageKind = AppFeedbackKind.error;
  bool _codeSent = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSend {
    final email = _emailController.text.trim();
    return email.contains('@') && email.contains('.') && !_busy;
  }

  bool get _canReset {
    final password = _passwordController.text;
    return _codeController.text.trim().length == 6 &&
        password.length >= 8 &&
        password == _confirmController.text &&
        !_busy;
  }

  Future<void> _sendCode() async {
    if (!_canSend) return;
    setState(() => _busy = true);
    final result =
        await AuthSession.instance.requestPasswordReset(_emailController.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) _codeSent = true;
    });
    _show(
      result.ok ? 'إذا كان البريد مسجّلاً، سيصلك رمز خلال دقائق' : result.message,
      success: result.ok,
    );
  }

  Future<void> _reset() async {
    if (!_canReset) return;
    setState(() => _busy = true);
    final result = await AuthSession.instance.resetPassword(
      email: _emailController.text,
      code: _codeController.text,
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      _show(result.message);
      return;
    }
    Navigator.of(context).pop((
      email: _emailController.text.trim(),
      password: _passwordController.text,
    ));
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
    if (!_codeSent) return null;
    final password = _passwordController.text;
    if (_codeController.text.trim().length != 6) return 'أدخل الرمز المكوّن من 6 أرقام';
    if (password.length < 8) return 'كلمة المرور يجب أن تتكون من 8 أحرف على الأقل';
    if (password != _confirmController.text) return 'كلمتا المرور غير متطابقتين';
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

    InputDecoration decoration(String hint, {Widget? suffixIcon}) {
      return authFieldDecoration(
        hint: hint,
        fillColor: surface,
        textSecondary: textSecondary,
        suffixIcon: suffixIcon,
      );
    }

    final visibilityToggle = IconButton(
      onPressed: () => setState(() => _obscure = !_obscure),
      icon: Icon(
        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: textSecondary,
      ),
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: WafferBackHeader(
        enabled: !_busy,
        title: 'نسيت كلمة المرور',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _codeSent
                    ? 'أدخل الرمز الذي وصلك على بريدك وكلمة مرور جديدة'
                    : 'أدخل بريدك وسنرسل لك رمزاً لإعادة التعيين',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 28),
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
                      enabled: !_busy && !_codeSent,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      onChanged: (_) => setState(() => _message = null),
                      style: TextStyle(color: textPrimary, fontSize: 16),
                      decoration: decoration('example@email.com'),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 16),
                      AuthFieldLabel(text: 'الرمز', color: textPrimary),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        maxLength: 6,
                        onChanged: (_) => setState(() => _message = null),
                        style: TextStyle(color: textPrimary, fontSize: 16),
                        decoration: decoration('123456'),
                      ),
                      const SizedBox(height: 8),
                      AuthFieldLabel(
                        text: 'كلمة المرور الجديدة',
                        color: textPrimary,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        enabled: !_busy,
                        obscureText: _obscure,
                        onChanged: (_) => setState(() => _message = null),
                        style: TextStyle(color: textPrimary, fontSize: 16),
                        decoration: decoration(
                          '8 أحرف على الأقل',
                          suffixIcon: visibilityToggle,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AuthFieldLabel(
                        text: 'تأكيد كلمة المرور',
                        color: textPrimary,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _confirmController,
                        enabled: !_busy,
                        obscureText: _obscure,
                        onChanged: (_) => setState(() => _message = null),
                        style: TextStyle(color: textPrimary, fontSize: 16),
                        decoration: decoration('أعد كتابة كلمة المرور'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'ملاحظاتك وأسماء أهدافك وقوائمك مشفّرة بكلمة المرور القديمة. '
                        'الموجود منها على هذا الجهاز يبقى، وما ليس على هذا الجهاز لا يمكن استرجاعه. '
                        'المبالغ لا تتأثر.',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              AppInlineMessage(message: _message, kind: _messageKind),
              AppPrimaryButton(
                label: _codeSent ? 'تعيين كلمة المرور' : 'إرسال الرمز',
                enabled: _codeSent ? _canReset : _canSend,
                onDisabledTap: () => _show(_missingReason),
                busy: _busy,
                onTap: _codeSent ? _reset : _sendCode,
              ),
              if (_codeSent)
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: Text(
                    'إعادة إرسال الرمز',
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
