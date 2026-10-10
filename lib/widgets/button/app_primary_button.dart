// The one primary action button of the app: full width, accent fill, white
// bold label. Sheets (SheetSaveButton), forms and screens all use it so the
// main action looks and behaves the same everywhere.
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

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
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
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
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontFamilyFallback: ['Tajawal'],
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 8),
                          Icon(icon, size: 20, color: Colors.white),
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
