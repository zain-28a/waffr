import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

/// Shared top bar for the app shell and settings-style screens.
class WafferPageHeader extends StatelessWidget implements PreferredSizeWidget {
  static const double height = 68;

  final Widget title;
  final Widget? leading;
  final bool centerTitle;
  final ValueListenable<bool>? elevated;

  const WafferPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.centerTitle = false,
    this.elevated,
  });

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    if (elevated == null) {
      return _HeaderChrome(
        title: title,
        leading: leading,
        centerTitle: centerTitle,
        elevated: false,
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: elevated!,
      builder: (context, isElevated, _) {
        return _HeaderChrome(
          title: title,
          leading: leading,
          centerTitle: centerTitle,
          elevated: isElevated,
        );
      },
    );
  }
}

class _HeaderChrome extends StatelessWidget {
  final Widget title;
  final Widget? leading;
  final bool centerTitle;
  final bool elevated;

  const _HeaderChrome({
    required this.title,
    required this.leading,
    required this.centerTitle,
    required this.elevated,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface,
            Color.alphaBlend(accent.withValues(alpha: 0.05), surface),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: elevated ? 0.10 : 0.05),
            blurRadius: elevated ? 16 : 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: accent.withValues(alpha: elevated ? 0.18 : 0.08),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: WafferPageHeader.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: leading,
                ),
                Expanded(
                  child: centerTitle
                      ? Center(child: title)
                      : Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 12),
                            child: title,
                          ),
                        ),
                ),
                if (centerTitle) const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
