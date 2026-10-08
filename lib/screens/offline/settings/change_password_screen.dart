// Change the account password. Other devices are signed out; data stays.

import 'package:flutter/material.dart';
import 'package:waffer/core/sync/auth_session.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/screens/offline/login/auth_fields.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSave {
    final next = _newController.text;
    return _currentController.text.isNotEmpty &&
        next.length >= 8 &&
        next == _confirmController.text &&
        next != _currentController.text &&
        !_busy;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _busy = true);
    final result = await AuthSession.instance.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showAppSnackBar(context, result.message);
      return;
    }
    showAppSnackBar(context, 'تم تغيير كلمة المرور', success: true);
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

    Widget field(
      String label,
      TextEditingController controller,
      String hint, {
      Widget? suffixIcon,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthFieldLabel(text: label, color: textPrimary),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: !_busy,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: textPrimary, fontSize: 16),
            decoration: authFieldDecoration(
              hint: hint,
              fillColor: surface,
              textSecondary: textSecondary,
              suffixIcon: suffixIcon,
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: WafferPageHeader(
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_forward_ios_rounded, color: textPrimary),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'تغيير كلمة المرور',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          field(
            'كلمة المرور الحالية',
            _currentController,
            '••••••••',
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
          field('كلمة المرور الجديدة', _newController, '8 أحرف على الأقل'),
          field(
            'تأكيد كلمة المرور الجديدة',
            _confirmController,
            'أعد كتابة كلمة المرور',
          ),
          Text(
            'سيتم تسجيل الخروج من أجهزتك الأخرى. بياناتك تبقى كما هي.',
            style: TextStyle(color: textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'حفظ',
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
