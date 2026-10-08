// Shared snackbars and dialogs: one visual language for the whole app.

import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/theme/app_palette.dart';

const String insufficientBalanceMessage =
    'المبلغ أكبر من رصيدك الحالي، لا يمكن إتمام العملية.';

enum AppFeedbackKind { success, error, warning, info }

class _FeedbackStyle {
  final Color background;
  final Color foreground;
  final Color accent;
  final IconData icon;

  const _FeedbackStyle({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.icon,
  });
}

_FeedbackStyle _styleFor(BuildContext context, AppFeedbackKind kind) {
  final palette = AppPalette.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return switch (kind) {
    AppFeedbackKind.success => _FeedbackStyle(
      background: palette.accent,
      foreground: Colors.white,
      accent: Colors.white,
      icon: Icons.check_rounded,
    ),
    AppFeedbackKind.error => _FeedbackStyle(
      background: palette.surface,
      foreground: palette.textPrimary,
      accent: isDark ? const Color(0xFFE38B8B) : const Color(0xFF8E3B3B),
      icon: Icons.error_outline_rounded,
    ),
    AppFeedbackKind.warning => _FeedbackStyle(
      background: palette.surface,
      foreground: palette.textPrimary,
      accent: isDark ? const Color(0xFFE2C27A) : const Color(0xFF8A6A24),
      icon: Icons.warning_amber_rounded,
    ),
    AppFeedbackKind.info => _FeedbackStyle(
      background: palette.surface,
      foreground: palette.textPrimary,
      accent: palette.accent,
      icon: Icons.info_outline_rounded,
    ),
  };
}

TextStyle _feedbackText(
  Color color, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: const ['Tajawal'],
    fontSize: size,
    fontWeight: weight,
    height: 1.4,
    color: color,
  );
}

// Branded floating notice. [success] remains for older call sites.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
  AppFeedbackKind? kind,
}) {
  final resolved =
      kind ?? (success ? AppFeedbackKind.success : AppFeedbackKind.error);
  final style = _styleFor(context, resolved);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: style.background,
      elevation: 8,
      duration: resolved == AppFeedbackKind.error ||
              resolved == AppFeedbackKind.warning
          ? const Duration(milliseconds: 3400)
          : const Duration(milliseconds: 2400),
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: style.accent.withValues(alpha: 0.18)),
      ),
      content: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: style.accent.withValues(alpha: resolved == AppFeedbackKind.success ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(style.icon, size: 16, color: style.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              textAlign: TextAlign.start,
              style: _feedbackText(style.foreground, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
    snackBarAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
  );
}

void showInsufficientBalanceMessage(BuildContext context) {
  showAppSnackBar(context, insufficientBalanceMessage);
}

// Fade and slide for every app dialog, including form dialogs.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'إغلاق',
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: builder(context),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AppDialogAction {
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool destructive;
  final bool enabled;

  const AppDialogAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.enabled = true,
  });
}

// Rounded dialog shell used by confirms and form dialogs.
class AppDialogFrame extends StatelessWidget {
  final String title;
  final String? message;
  final AppFeedbackKind kind;
  final Widget? child;
  final List<AppDialogAction> actions;

  const AppDialogFrame({
    super.key,
    required this.title,
    this.message,
    this.kind = AppFeedbackKind.info,
    this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = _styleFor(context, kind);
    final width = MediaQuery.sizeOf(context).width;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width > 460 ? 400 : width - 40,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(style.icon, color: style.accent, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: _feedbackText(
                palette.textPrimary,
                size: 17,
                weight: FontWeight.w800,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: _feedbackText(
                  palette.textSecondary,
                  size: 14,
                  weight: FontWeight.w500,
                ),
              ),
            ],
            if (child != null) ...[
              const SizedBox(height: 14),
              child!,
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: AppDialogActionButton(action: actions[i])),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// One dialog action styled like the confirm dialogs. Public for custom frames.
class AppDialogActionButton extends StatelessWidget {
  final AppDialogAction action;

  const AppDialogActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final destructiveColor =
        isDark ? const Color(0xFFE38B8B) : const Color(0xFF8E3B3B);

    if (!action.primary && !action.destructive) {
      return TextButton(
        onPressed: action.enabled ? action.onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: palette.textSecondary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          action.label,
          style: _feedbackText(palette.textSecondary, weight: FontWeight.w700),
        ),
      );
    }

    final background = action.destructive ? destructiveColor : palette.accent;
    return FilledButton(
      onPressed: action.enabled ? action.onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        disabledBackgroundColor: background.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Text(
        action.label,
        style: _feedbackText(Colors.white, weight: FontWeight.w700),
      ),
    );
  }
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
  AppFeedbackKind kind = AppFeedbackKind.warning,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    builder: (context) {
      return AppDialogFrame(
        title: title,
        message: message,
        kind: destructive ? AppFeedbackKind.error : kind,
        actions: [
          AppDialogAction(
            label: cancelLabel,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppDialogAction(
            label: confirmLabel,
            primary: !destructive,
            destructive: destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    },
  );
  return result == true;
}

Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'حسناً',
}) {
  return showAppDialog<void>(
    context: context,
    builder: (context) {
      return AppDialogFrame(
        title: title,
        message: message,
        kind: AppFeedbackKind.info,
        actions: [
          AppDialogAction(
            label: actionLabel,
            primary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    },
  );
}

// Keeps the accent token available to dialogs that still paint custom fields.
Color appFeedbackAccent(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.darkAccent : AppColors.lightAccent;
}
