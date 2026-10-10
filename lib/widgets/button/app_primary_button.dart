// The one primary action button of the app: full width, accent fill, white
// bold label. Sheets (SheetSaveButton), forms and screens all use it so the
// main action looks and behaves the same everywhere.
import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';

class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// Greyed out when false. Taps then go to [onDisabledTap], if given, so a
  /// form can explain what is missing.
  final bool enabled;
  final VoidCallback? onDisabledTap;

  /// Shows a spinner instead of the label and ignores taps.
  final bool busy;
  final IconData? icon;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.onDisabledTap,
    this.busy = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    // Disabled fills are grey, so their label switches to a grey that
    // stays readable in both themes.
    final onAccent = enabled || busy
        ? AppColors.onAccentOf(context)
        : (isDark
            ? AppColors.darkTextPrimary.withValues(alpha: 0.6)
            : AppColors.lightOnAccent);
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final VoidCallback? handler =
        busy ? null : (enabled ? onTap : onDisabledTap);

    return Semantics(
      button: true,
      enabled: enabled && !busy,
      child: Material(
        color: enabled || busy ? accent : textSecondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: handler,
          child: SizedBox(
            height: 58,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: onAccent,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontFamilyFallback: ['Tajawal'],
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: onAccent,
                            ),
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 8),
                          Icon(icon, size: 20, color: onAccent),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
