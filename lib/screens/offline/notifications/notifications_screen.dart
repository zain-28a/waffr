import 'package:flutter/material.dart';
import 'package:waffer/data/models/app_notification.dart';
import 'package:waffer/data/services/notification_service.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/brand/waffer_page_header.dart';
import 'package:waffer/widgets/containers/glass.dart';

// Notifications page: mute toggle, mark-all-read, clear history, grouped list.

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _service.ensureLoaded();
  }

  // Clears history only — balance, savings, goals, and mute stay intact.
  Future<void> _confirmClear() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'مسح سجل الإشعارات',
      message:
          'سيتم حذف سجل الإشعارات فقط. لن يتأثر رصيدك أو ادخارك أو أهدافك، ولن يتغيّر إعداد الكتم.',
      confirmLabel: 'مسح السجل',
      destructive: true,
    );

    if (confirmed == true) {
      await _service.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            WafferPageHeader(
              applySafeArea: false,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: colors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'الإشعارات',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final items = _service.notifications;
        final groups = NotificationTimeGroup.from(items);
        final hasUnread = _service.unreadCount > 0;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      if (hasUnread)
                        _HeaderAction(
                          icon: Icons.done_all_rounded,
                          tooltip: 'تعيين الكل كمقروء',
                          onTap: _service.markAllRead,
                        ),
                      if (items.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _HeaderAction(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'مسح السجل',
                          onTap: _confirmClear,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MuteControl(
                    muted: _service.isMuted,
                    onTap: _service.toggleMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const _EmptyNotifications()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        return _NotificationGroupView(
                          group: groups[index],
                          onOpen: _service.markRead,
                        );
                      },
                    ),
            ),
          ],
        );
      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Toggle for whether new alerts are written to the history.
class _MuteControl extends StatelessWidget {
  final bool muted;
  final VoidCallback onTap;

  const _MuteControl({
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: muted ? 0.08 : 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  muted
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_rounded,
                  color: muted ? colors.textSecondary : colors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      muted ? 'الإشعارات مكتومة' : 'الإشعارات مفعلة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      muted
                          ? 'لن تُضاف تنبيهات جديدة إلى السجل'
                          : 'ستصلك تنبيهات الأحداث المهمة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                size: 20,
                color: muted ? colors.textSecondary : colors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.accent.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: colors.textPrimary.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 42,
              color: colors.textSecondary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد إشعارات بعد',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ستظهر هنا تنبيهات الرصيد والأهداف والادخار عند حدوثها',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One time bucket (e.g. Today) and its tiles.
class _NotificationGroupView extends StatelessWidget {
  final NotificationTimeGroup group;
  final ValueChanged<String> onOpen;

  const _NotificationGroupView({
    required this.group,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Text(
              group.label,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          for (var i = 0; i < group.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _NotificationTile(
              notification: group.items[i],
              onTap: () => onOpen(group.items[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _NotificationColors.of(context);
    final unread = !notification.isRead;
    final icon = _iconFor(notification.type);
    final important = notification.priority == NotificationPriority.warning ||
        notification.priority == NotificationPriority.important ||
        notification.priority == NotificationPriority.success;
    final iconColor = unread || important ? colors.accent : colors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: GlassContainer(
          colorType: GlassColorType.surface,
          borderRadius: 22,
          tintOpacity: unread ? 0.92 : 0.78,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: unread ? 0.16 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (unread) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                              fontSize: 14.5,
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                              color: colors.textPrimary.withValues(
                                alpha: unread ? 1 : 0.78,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatTime(notification.createdAt),
                          style: TextStyle(
                            fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDate(notification.createdAt),
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 11,
                        color: colors.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(NotificationType type) {
    return switch (type) {
      NotificationType.balanceWarning => Icons.account_balance_wallet_outlined,
      NotificationType.highSpending => Icons.trending_up_rounded,
      NotificationType.largeExpense => Icons.priority_high_rounded,
      NotificationType.goalReached => Icons.emoji_events_outlined,
      NotificationType.goalProgress => Icons.flag_outlined,
      NotificationType.savingsTransferred => Icons.savings_outlined,
      NotificationType.recurringPeriodCompleted => Icons.event_available_outlined,
      NotificationType.recurringExpenseBlocked => Icons.block_rounded,
      NotificationType.recurringExpenseApplied => Icons.event_repeat_rounded,
    };
  }
}

// Theme colors for this screen so tiles stay consistent.
class _NotificationColors {
  final Color surface;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const _NotificationColors({
    required this.surface,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  factory _NotificationColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _NotificationColors(
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      accent: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      textPrimary:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      textSecondary:
          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
    );
  }
}
