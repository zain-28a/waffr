// Privacy hub: account data, cloud sync, app lock, and local reset detail pages.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/widgets/button/app_primary_button.dart';
import 'package:waffr/data/services/local_data_reset.dart';
import 'package:waffr/core/security/app_lock.dart';
import 'package:waffr/core/sync/auth_session.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/core/theme/app_palette.dart';

part 'privacy_detail_pages.dart';
part 'privacy_widgets.dart';

/// Entry list that opens deeper privacy/security detail pages.
class PrivacySecurityScreen extends StatefulWidget {
  final dynamic appFlowController;

  /// Creates a [PrivacySecurityScreen].
  const PrivacySecurityScreen({super.key, this.appFlowController});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

/// State of [PrivacySecurityScreen].
class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final ValueNotifier<bool> _headerElevated = ValueNotifier(false);

  bool _loggedIn = false;
  bool _appLock = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _headerElevated.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loggedIn = await AuthSession.instance.isLoggedIn();
    final appLock = await AppLock.isEnabled();

    if (!mounted) return;

    setState(() {
      _loggedIn = loggedIn;
      _appLock = appLock;
      _loading = false;
    });
  }

  Future<void> _openDetail(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _PrivacyColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            WaffrBackHeader(
              elevated: _headerElevated,
              title: 'الخصوصية والأمان',
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: colors.accent),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth != 0) return false;
                        final next = notification.metrics.pixels > 6;
                        if (_headerElevated.value != next) {
                          _headerElevated.value = next;
                        }
                        return false;
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        children: staggered([
                          _SectionLabel(
                            title: 'بياناتك',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.badge_outlined,
                                title: 'بيانات الحساب',
                                colors: colors,
                                onTap: () =>
                                    _openDetail(const _AccountDataDetailPage()),
                              ),
                              _SettingsRow(
                                icon: Icons.cloud_sync_outlined,
                                title: 'المزامنة السحابية',
                                colors: colors,
                                status: _loggedIn ? 'مفعّلة' : 'وضع الضيف',
                                statusEmphasis: _loggedIn,
                                onTap: () => _openDetail(
                                  _CloudSyncDetailPage(loggedIn: _loggedIn),
                                ),
                              ),
                              _SettingsRow(
                                icon: Icons.sync_alt_rounded,
                                title: 'البيانات المتزامنة',
                                colors: colors,
                                showDivider: false,
                                onTap: () =>
                                    _openDetail(const _SyncedDataDetailPage()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(
                            title: 'حماية التطبيق',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.lock_outline_rounded,
                                title: 'قفل التطبيق',
                                colors: colors,
                                status: _appLock ? 'مفعّل' : 'غير مفعّل',
                                statusEmphasis: _appLock,
                                showDivider: false,
                                onTap: () => _openDetail(
                                  _AppLockDetailPage(
                                    appFlowController: widget.appFlowController,
                                    auth: _auth,
                                    initiallyEnabled: _appLock,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel(
                            title: 'البيانات والحساب',
                            color: colors.textSecondary,
                          ),
                          _SettingsGroup(
                            surface: colors.surface,
                            children: [
                              _SettingsRow(
                                icon: Icons.delete_outline_rounded,
                                title: 'إعادة ضبط البيانات المحلية',
                                colors: colors,
                                showDivider: false,
                                onTap: () =>
                                    _openDetail(const _LocalResetDetailPage()),
                              ),
                            ],
                          ),
                        ]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
