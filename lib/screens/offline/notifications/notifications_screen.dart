import 'package:flutter/material.dart';
import 'package:waffr/widgets/motion/motion.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/data/models/app_notification.dart';
import 'package:waffr/data/services/notification_service.dart';
import 'package:waffr/data/services/system_notifications.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/screens/offline/obligations/obligations_sheet.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/app_list_tile.dart';
import 'package:waffr/widgets/containers/glass.dart';

// Notifications page: mute toggle, mark-all-read, clear history, grouped list.

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final NotificationService _service = NotificationService.instance;

  // False when the phone blocks Waffr's notifications; null when unknown.
  bool? _deviceAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.ensureLoaded();
    _refreshDevicePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check after the user comes back from the phone settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDevicePermission();
  }

  Future<void> _refreshDevicePermission() async {
    final allowed =
        await SystemNotifications.instance.deviceNotificationsEnabled();
    if (mounted) setState(() => _deviceAllowed = allowed);
  }

  Future<void> _allowDeviceNotifications() async {
    final granted = await SystemNotifications.instance.requestPermission();
    await _refreshDevicePermission();
    if (!mounted || granted) return;
    // Android stops showing the prompt after it was refused twice.
    await showAppInfoDialog(
      context,
      title: 'إشعارات الجهاز متوقفة',
      message:
          'لم يعد الهاتف يعرض طلب الإذن. لتفعيل الإشعارات افتح إعدادات الهاتف، ثم التطبيقات، ثم وفّر، ثم الإشعارات، وفعّلها.',
    );
  }

  // Clears history only — balance, savings, goals, and mute stay intact.
  // Marks the alert read; obligation alerts also open where they can be acted on.
  void _open(AppNotification notification) {
    _service.markRead(notification.id);
    switch (notification.type) {
      case NotificationType.recurringExpenseDue:
        showDueObligationsSheet(context);
      case NotificationType.recurringExpenseBlocked:
      case NotificationType.recurringExpenseApplied:
      case NotificationType.recurringExpenseUpcoming:
        showObligationsSheet(context);
      default:
        break;
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'مسح سجل الإشعارات',
      message:
          'سيتم حذف سجل الإشعارات فقط. لن يتأثر رصيدك أو مبالغك الموفَّرة أو أهدافك، ولن يتغيّر إعداد الكتم.',
      confirmLabel: 'مسح السجل',
      destructive: true,
    );

    if (confirmed == true) {
      await _service.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            WaffrBackHeader(
              applySafeArea: false,
              title: 'الإشعارات',
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
                  if (_deviceAllowed == false) ...[
                    const SizedBox(height: 10),
                    AppListTile(
                      icon: Icons.notifications_off_outlined,
                      title: 'إشعارات الجهاز متوقفة',
                      subtitle: 'اسمح لوفّر بإرسال التنبيهات إلى هاتفك',
                      status: 'سماح',
                      statusOn: true,
                      onTap: _allowDeviceNotifications,
                    ),
                  ],
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
                        final view = _NotificationGroupView(
                          group: groups[index],
                          onOpen: _open,
                        );
                        // Only the first screenful animates in.
                        return index < 6
                            ? Reveal(index: index, child: view)
                            : view;
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
                      muted ? 'الإشعارات مكتومة' : 'الإشعارات مفعّلة',
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
    return const Center(
      child: AppEmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'لا توجد إشعارات بعد',
        message: 'ستظهر هنا تنبيهات الرصيد والأهداف والتوفير والالتزامات عند حدوثها',
      ),
    );
  }
}

// One time bucket (e.g. Today) and its tiles.
class _NotificationGroupView extends StatelessWidget {
  final NotificationTimeGroup group;
  final ValueChanged<AppNotification> onOpen;

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
              onTap: () => onOpen(group.items[i]),
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
      NotificationType.recurringExpenseUpcoming => Icons.event_busy_outlined,
      NotificationType.recurringExpenseDue => Icons.pending_actions_rounded,
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
