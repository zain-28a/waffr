import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffer/core/theme/app_color.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const LockScreen({
    super.key,
    required this.onAuthenticated,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _loading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      final supported = await _auth.isDeviceSupported();

      if (!supported) {
        widget.onAuthenticated();
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: '.',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (authenticated && mounted) {
        widget.onAuthenticated();
      }
    } on LocalAuthException catch (_) {
      // المستخدم ألغى البصمة أو فشلت المحاولة
    } catch (_) {
      // أي خطأ آخر
    } finally {
      if (mounted) {
        // نعطي Android لحظة حتى ينهي نافذة المصادقة
        await Future.delayed(
          const Duration(milliseconds: 300),
        );

        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;

    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final accent = isDark
        ? AppColors.darkAccent
        : AppColors.lightAccent;

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 70,
              color: accent,
            ),

            const SizedBox(height: 25),

            Text(
              'مقفل',
              style: TextStyle(
                color: textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'افتح القفل للدخول إلى التطبيق',
              style: TextStyle(
                color: textPrimary.withValues(alpha: 0.6),
                fontSize: 14,
                fontFamily: 'Tajawal',
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: _loading ? null : _authenticate,
              icon: const Icon(Icons.fingerprint),
              label: const Text(
                'فتح القفل',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}