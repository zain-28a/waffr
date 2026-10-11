// Usage profile. Account editing stays in Settings.

import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/screens/shell/app_shell_scope.dart';
import 'package:waffr/core/insights/profile_snapshot.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/usage/usage_duration.dart';
import 'package:waffr/data/services/profile_identity.dart';
import 'package:waffr/data/services/usage_streak_service.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/data/stores/transaction_store.dart';
import 'package:waffr/widgets/brand/profile_avatar.dart';
import 'package:waffr/screens/offline/profile/balance_scale_card.dart';
import 'package:waffr/screens/offline/profile/streak_card.dart';
import 'package:waffr/core/insights/money_balance.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/core/insights/smart/smart_insight.dart';
import 'package:waffr/widgets/smart/smart_analysis_button.dart';

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<int> tabIndex;

  const ProfileScreen({super.key, required this.tabIndex});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  static const int _tab = 4;

  final TransactionStore _store = TransactionStore.instance;

  // Bumped each time the tab is opened so the streak card plays again.
  int _streakReplay = 0;
  late final Listenable _data = Listenable.merge([
    _store,
    CurrencyStore.instance,
    UsageStreakService.instance,
    ProfileIdentity.instance,
  ]);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tabIndex.addListener(_onTab);
    _store.ensureLoaded();
    UsageStreakService.instance.ensureLoaded();
    ProfileIdentity.instance.reload();
  }

  @override
  void dispose() {
    widget.tabIndex.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (widget.tabIndex.value != _tab) return;
    ProfileIdentity.instance.reload();
    setState(() => _streakReplay++);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = AppPalette.of(context);

    return AnimatedBuilder(
      animation: _data,
      builder: (context, _) {
        final snapshot = ProfileSnapshot.fromStore(_store);
        final streak = UsageStreakService.instance;
        final identity = ProfileIdentity.instance;
        final started = streak.startedAt;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, kFloatingNavClearance),
          children: staggered([
            _ProfileHeader(identity: identity, palette: palette),
            const SizedBox(height: kCardGap),
            StreakCard(
              count: streak.isLoaded && streak.count > 0 ? streak.count : 1,
              lastDay: streak.lastDay,
              replayToken: _streakReplay,
            ),
            const SizedBox(height: kCardGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: started == null
                      ? const SizedBox.shrink()
                      : _UsageDuration(
                          text: usageDurationText(started, DateTime.now()),
                          palette: palette,
                        ),
                ),
                const SizedBox(width: 8),
                const SmartAnalysisButton(
                  scope: InsightScope.profile,
                  large: true,
                ),
              ],
            ),
            const SizedBox(height: kCardGap),
            _UsageStats(snapshot: snapshot, palette: palette),
            const SizedBox(height: kCardGap),
            BalanceScaleCard(
              balance: MoneyBalance.fromTransactions(
                _store.transactions,
                currencyCode: CurrencyStore.instance.activeCode,
                now: DateTime.now(),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ProfileIdentity identity;
  final AppPalette palette;

  const _ProfileHeader({
    required this.identity,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final email = identity.displayEmail;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            accent: palette.accent,
            radius: 46,
            signedIn: identity.isLoggedIn,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: SizedBox(
              height: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    identity.displayName,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 28,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: 15,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageDuration extends StatelessWidget {
  final String text;
  final AppPalette palette;

  const _UsageDuration({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مدة الاستخدام',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontFamilyFallback: const ['Tajawal'],
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontFamilyFallback: const ['Tajawal'],
            fontSize: 26,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _UsageStats extends StatelessWidget {
  final ProfileSnapshot snapshot;
  final AppPalette palette;

  const _UsageStats({required this.snapshot, required this.palette});

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: snapshot.expenseCount,
            label: 'عمليات الصرف',
            palette: palette,
          ),
        ),
        const SizedBox(width: gap),
        Expanded(
          child: _StatTile(
            value: snapshot.incomeCount,
            label: 'عمليات الدخل',
            palette: palette,
          ),
        ),
        const SizedBox(width: gap),
        Expanded(
          child: _StatTile(
            value: snapshot.goalCount,
            label: 'أهداف التوفير' ,
            palette: palette,
          ),
        ),
        const SizedBox(width: gap),
        Expanded(
          child: _StatTile(
            value: snapshot.savingsCount,
            label:  'عمليات التوفير',
            palette: palette,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  final AppPalette palette;

  const _StatTile({
    required this.value,
    required this.label,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontSize: 10.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
