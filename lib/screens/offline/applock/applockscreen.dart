import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffer/widgets/button/app_primary_button.dart';
import 'package:waffer/core/theme/app_color.dart';

// Blocks the app until device auth (biometrics or PIN) succeeds.

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

  // Prompts local_auth; unsupported devices skip straight through.
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
      // User cancelled or biometrics failed — stay locked.
    } catch (_) {
      // Unexpected auth error — stay locked.
    } finally {
      if (mounted) {
        // Brief pause so Android can dismiss the system auth UI first.
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
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'افتح القفل للدخول إلى التطبيق',
              style: TextStyle(
                color: textPrimary.withValues(alpha: 0.6),
                fontSize: 14,
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              ),
            ),

            const SizedBox(height: 30),

            AppPrimaryButton(
              label: 'فتح القفل',
              icon: Icons.fingerprint,
              busy: _loading,
              onTap: _authenticate,
            ),
          ],
        ),
      ),
    );
  }
}
