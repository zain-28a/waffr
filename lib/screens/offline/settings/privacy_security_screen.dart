// Privacy and security: the app-lock switch and the reset of this device's
// data. The page holds controls only, no explanatory copy.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffr/core/security/app_lock.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/data/services/local_data_reset.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';

/// App lock and local reset. Opened from settings.
class PrivacySecurityScreen extends StatefulWidget {
  /// The root app flow state (from `main.dart`), or null. Told when the
  /// lock is switched so it can refresh its lock state.
  final dynamic appFlowController;

  /// Creates a [PrivacySecurityScreen].
  const PrivacySecurityScreen({super.key, this.appFlowController});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Null until the stored lock flag is read.
  bool? _appLock;

  /// True while the device prompt or the prefs write runs.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLock.isEnabled().then((enabled) {
      if (mounted) setState(() => _appLock = enabled);
    });
  }

  /// Enables after device auth, disables by clearing the flag, and tells the
  /// app flow either way.
  Future<void> _toggleLock(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    final result = await AppLock.setEnabled(
      enabled: value,
      auth: _auth,
      onEnabled: () => widget.appFlowController?.refreshAppLockState(
        sessionAuthenticated: true,
      ),
      onDisabled: () => widget.appFlowController?.refreshAppLockState(),
    );
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (result == AppLockToggleResult.enabled) _appLock = true;
      if (result == AppLockToggleResult.disabled) _appLock = false;
    });

    switch (result) {
      case AppLockToggleResult.enabled:
        showAppSnackBar(context, 'تم تفعيل قفل التطبيق', success: true);
      case AppLockToggleResult.disabled:
        showAppSnackBar(context, 'تم إيقاف قفل التطبيق', success: true);
      case AppLockToggleResult.unsupported:
        showAppSnackBar(
          context,
          'جهازك لا يدعم البصمة أو قفل الشاشة',
          kind: AppFeedbackKind.warning,
        );
      case AppLockToggleResult.cancelled:
        break;
    }
  }

  /// Confirms, wipes this device's data (the server account stays), then
  /// returns to the first route.
  Future<void> _resetDevice() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'إعادة ضبط البيانات المحلية',
      message:
          'ستُحذف البيانات المحفوظة على هذا الجهاز فقط، ولن يُحذف حسابك. '
          'لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف البيانات',
      destructive: true,
    );
    if (confirm != true || !mounted) return;

    await LocalDataReset.resetCurrentDevice();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lock = _appLock;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: const WaffrBackHeader(title: 'الخصوصية والأمان'),
      body: AuroraPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const AppSectionTitle(title: 'حماية التطبيق'),
            AppListTile(
              icon: AppIcons.lock,
              title: 'قفل التطبيق',
              showChevron: false,
              trailing: Switch(
                value: lock ?? false,
                onChanged: lock == null || _busy ? null : _toggleLock,
              ),
              onTap: lock == null || _busy ? null : () => _toggleLock(!lock),
            ),
            const SizedBox(height: 22),
            const AppSectionTitle(title: 'البيانات'),
            AppListTile(
              icon: AppIcons.trash,
              title: 'إعادة ضبط البيانات المحلية',
              destructive: true,
              onTap: _resetDevice,
            ),
          ],
        ),
      ),
    );
  }
}
