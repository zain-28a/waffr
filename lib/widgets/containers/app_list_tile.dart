// Settings-style rows shared by Settings, Account and Privacy screens:
// one card per row with an icon box, title, optional subtitle or status,
// and a chevron. Section titles above groups of rows use AppSectionTitle.
import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_color.dart';

TextStyle _tileText(Color color, double size, FontWeight weight) => TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

class AppListTile extends StatelessWidget {
  final IconData icon;

  /// Drawn in the icon box instead of [icon] (e.g. the smart sparkle).
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// Short state shown as a chip (e.g. «مفعّل»); [statusOn] tints it.
  final String? status;
  final bool statusOn;

  /// Replaces the chevron (e.g. a switch).
  final Widget? trailing;
  final bool showChevron;
  final bool busy;
  final bool destructive;
  final VoidCallback? onTap;

  const AppListTile({
    super.key,
    required this.icon,
    required this.title,
    this.leading,
    this.subtitle,
    this.status,
    this.statusOn = false,
    this.trailing,
    this.showChevron = true,
    this.busy = false,
    this.destructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final danger = AppColors.destructiveOf(context);
    final tint = destructive ? danger : accent;

    Widget? end;
    if (busy) {
      end = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    } else if (trailing != null) {
      end = trailing;
    } else if (showChevron) {
      end = Icon(
        Icons.arrow_back_ios_new_rounded,
        color: textSecondary.withValues(alpha: 0.5),
        size: 16,
      );
    }

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: leading ?? Icon(icon, color: tint, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _tileText(
                        destructive ? danger : textPrimary,
                        15,
                        FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: _tileText(textSecondary, 12, FontWeight.w400),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                _StatusChip(
                  label: status!,
                  on: statusOn,
                  accent: accent,
                  muted: textSecondary,
                ),
              ],
              if (end != null) ...[
                const SizedBox(width: 8),
                end,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool on;
  final Color accent;
  final Color muted;

  const _StatusChip({
    required this.label,
    required this.on,
    required this.accent,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final color = on ? accent : muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: on ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: _tileText(color, 11.5, FontWeight.w700)),
    );
  }
}

/// Small grey heading above a group of [AppListTile]s.
class AppSectionTitle extends StatelessWidget {
  final String title;

  const AppSectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 5, bottom: 10),
      child: Text(title, style: _tileText(textSecondary, 14, FontWeight.bold)),
    );
  }
}
