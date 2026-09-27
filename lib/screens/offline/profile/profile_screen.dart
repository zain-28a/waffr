// Usage profile. Account editing stays in Settings.

import 'package:flutter/material.dart';
import 'package:waffer/core/insights/profile_snapshot.dart';
import 'package:waffer/core/theme/app_palette.dart';
import 'package:waffer/core/usage/usage_duration.dart';
import 'package:waffer/data/services/profile_identity.dart';
import 'package:waffer/data/services/usage_streak_service.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/data/stores/transaction_store.dart';
import 'package:waffer/widgets/brand/profile_avatar.dart';
import 'package:waffer/widgets/charts/savings_spending_bar.dart';
import 'package:waffer/widgets/containers/glass.dart';

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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            _ProfileHeader(
              identity: identity,
              palette: palette,
              streakCount: streak.isLoaded ? streak.count : 1,
            ),
            if (started != null) ...[
              const SizedBox(height: 18),
              _UsageDuration(
                text: usageDurationText(started, DateTime.now()),
                palette: palette,
              ),
            ],
            const SizedBox(height: 22),
            _UsageStats(snapshot: snapshot, palette: palette),
            const SizedBox(height: 16),
            GlassContainer(
              colorType: GlassColorType.surface,
              borderRadius: 22,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الصرف والتوفير',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SavingsSpendingBar(
                    savings: snapshot.saved,
                    spending: snapshot.spent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ProfileIdentity identity;
  final AppPalette palette;
  final int streakCount;

  const _ProfileHeader({
    required this.identity,
    required this.palette,
    required this.streakCount,
  });

  @override
  Widget build(BuildContext context) {
    final email = identity.displayEmail;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(
                photoPath: identity.photoPath,
                accent: palette.accent,
                radius: 46,
                placeholder: !identity.isLoggedIn && identity.photoPath == null,
              ),
              const SizedBox(height: 14),
              _StreakChip(count: streakCount, palette: palette),
            ],
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

class _StreakChip extends StatefulWidget {
  final int count;
  final AppPalette palette;

  const _StreakChip({
    required this.count,
    required this.palette,
  });

  @override
  State<_StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<_StreakChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: palette.textPrimary,
    );
    final firstDay = widget.count <= 1;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_enter.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: GlassContainer(
                colorType: GlassColorType.surface,
                borderRadius: 22,
                padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                child: firstDay
                    ? Text('اليوم الأول', style: style)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.rtl,
                        children: [
                          Text('${widget.count}', style: style),
                          const SizedBox(width: 4),
                          Text('أيام متواصلة', style: style),
                        ],
                      ),
              ),
            ),
          );
        },
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
            label:  'عمليات الادخار',
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
