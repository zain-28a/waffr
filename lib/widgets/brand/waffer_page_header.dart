// Shared top app bar for the shell and settings-style screens.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';

/// Fixed-height page header with optional scroll-elevation shadow.
class WafferPageHeader extends StatelessWidget implements PreferredSizeWidget {
  static const double height = 68;

  final Widget title;
  final Widget? leading;
  final double leadingWidth;
  final bool centerTitle;
  final ValueListenable<bool>? elevated;
  final bool applySafeArea;

  const WafferPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.leadingWidth = 48,
    this.centerTitle = false,
    this.elevated,
    this.applySafeArea = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    if (elevated == null) {
        return _HeaderChrome(
          title: title,
          leading: leading,
          leadingWidth: leadingWidth,
          centerTitle: centerTitle,
          elevated: false,
          applySafeArea: applySafeArea,
        );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: elevated!,
      builder: (context, isElevated, _) {
        return _HeaderChrome(
          title: title,
          leading: leading,
          leadingWidth: leadingWidth,
          centerTitle: centerTitle,
          elevated: isElevated,
          applySafeArea: applySafeArea,
        );
      },
    );
  }
}

/// Gradient bar chrome, shadow, and title/leading layout.
class _HeaderChrome extends StatelessWidget {
  final Widget title;
  final Widget? leading;
  final double leadingWidth;
  final bool centerTitle;
  final bool elevated;
  final bool applySafeArea;

  const _HeaderChrome({
    required this.title,
    required this.leading,
    required this.leadingWidth,
    required this.centerTitle,
    required this.elevated,
    required this.applySafeArea,
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
      child: applySafeArea
          ? SafeArea(bottom: false, child: _bar)
          : _bar,
    );
  }

  Widget get _bar {
    return SizedBox(
      height: WafferPageHeader.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: leadingWidth,
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
            if (centerTitle) SizedBox(width: leadingWidth),
          ],
        ),
      ),
    );
  }
}
