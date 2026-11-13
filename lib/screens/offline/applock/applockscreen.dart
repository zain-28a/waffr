// App-lock screen: asks for device authentication before the app opens.

import 'package:waffr/widgets/brand/waffr_mood_logo.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffr/widgets/button/app_primary_button.dart';
import 'package:waffr/core/theme/app_palette.dart';

/// Blocks the app until device auth (biometrics or PIN) succeeds. Shown by
/// `main.dart` over the hidden shell while the app lock is on.
class LockScreen extends StatefulWidget {
  /// Called once device auth succeeds (or the device has no auth support).
  final VoidCallback onAuthenticated;

  /// Creates a [LockScreen].
  const LockScreen({super.key, required this.onAuthenticated});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

/// State of [LockScreen]. Prompts automatically after the first frame and
/// again on each tap of the unlock button.
class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  /// A system prompt is open (or just closed); drops repeat taps and shows
  /// the button's busy state.
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  /// Prompts local_auth; unsupported devices skip straight through.
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
        await Future.delayed(const Duration(milliseconds: 300));

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
    final palette = AppPalette.of(context);

    final bg = palette.background;

    final textPrimary = palette.textPrimary;

    final accent = palette.accent;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBackdrop(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // The wallet with a lock badge, title, hint, then the button.
              children: [
                SizedBox.square(
                  dimension: 108,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const WaffrMoodLogo(size: 108, idle: true),
                      PositionedDirectional(
                        bottom: -4,
                        end: -6,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: bg, width: 3),
                          ),
                          child: Icon(
                            AppIcons.lock,
                            size: 18,
                            color: palette.onAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                Text(
                  'مقفل',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                    fontFamilyFallback: ['Tajawal'],
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'افتح القفل للدخول إلى التطبيق',
                  style: TextStyle(
                    color: textPrimary.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontFamily: 'Outfit',
                    fontFamilyFallback: ['Tajawal'],
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: 200,
                  child: AppPrimaryButton(
                    label: 'فتح القفل',
                    icon: AppIcons.fingerprint,
                    busy: _loading,
                    onTap: _authenticate,
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
