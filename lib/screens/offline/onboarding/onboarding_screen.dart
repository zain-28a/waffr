// First-launch introduction: three short pages where the wallet character
// presents what Waffr does, before the sign-in choice.

import 'package:flutter/material.dart';
import 'package:waffr/core/insights/smart/wallet_mood.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/widgets/brand/waffr_mood_logo.dart';
import 'package:waffr/widgets/button/app_primary_button.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';
import 'package:waffr/widgets/motion/pressable.dart';

/// One page of the introduction.
class _Page {
  final String title;
  final String body;

  /// The face the wallet wears on this page.
  final SmileForm face;

  /// Small marks around the wallet that hint at the feature.
  final List<IconData> marks;

  const _Page({
    required this.title,
    required this.body,
    required this.face,
    required this.marks,
  });
}

/// Three swipeable pages with a "next" button, page dots and a skip link.
/// Calls [onDone] when the user finishes or skips.
class OnboardingScreen extends StatefulWidget {
  /// Called once the introduction is over.
  final VoidCallback onDone;

  /// Creates an [OnboardingScreen].
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_Page> _pages = [
    _Page(
      title: 'سجّل مصروفك في ثوانٍ',
      body:
          'أضف دخلك ومصروفك بلوحة أرقام سريعة، '
          'واعرف في أي لحظة كم بقي معك.',
      face: SmileForm.happy,
      marks: [AppIcons.arrowUpRight, AppIcons.receipt, AppIcons.banknote],
    ),
    _Page(
      title: 'وفّر لأهدافك',
      body:
          'حدّد هدفاً ونسبة من دخلك، '
          'ووفّر يقتطعها ويتابع تقدّمك نحوه.',
      face: SmileForm.excellent,
      marks: [AppIcons.piggyBank, AppIcons.target, AppIcons.trophy],
    ),
    _Page(
      title: 'تحليل يفهم أرقامك',
      body:
          'ملاحظات واضحة عن صرفك وتوفيرك، '
          'تُحسب على جهازك ولا تغادره.',
      face: SmileForm.pleased,
      marks: [AppIcons.lightbulb, AppIcons.chartLine, AppIcons.shieldCheck],
    ),
  ];

  final PageController _controller = PageController();
  int _page = 0;

  bool get _last => _page == _pages.length - 1;

  void _next() {
    if (_last) {
      AppHaptics.success();
      widget.onDone();
      return;
    }
    _controller.nextPageFor(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBackdrop(),
          SafeArea(
            child: Column(
              children: [
                // Skip, at the end of the top row.
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AnimatedOpacity(
                      duration: AppMotion.of(context, AppMotion.fast),
                      opacity: _last ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: Pressable(
                          onTap: _last ? null : widget.onDone,
                          depth: 0.06,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'تخطي',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontFamilyFallback: const ['Tajawal'],
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) {
                      AppHaptics.selection();
                      setState(() => _page = index);
                    },
                    itemBuilder: (context, index) =>
                        _PageView(page: _pages[index], active: index == _page),
                  ),
                ),
                _Dots(count: _pages.length, index: _page),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: AppPrimaryButton(
                    label: _last ? 'ابدأ' : 'التالي',
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The wallet with its marks, then the page's title and text.
class _PageView extends StatelessWidget {
  final _Page page;

  /// True for the page on screen; its wallet breathes.
  final bool active;

  const _PageView({required this.page, required this.active});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = (constraints.maxHeight * 0.42).clamp(150.0, 240.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: art,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // A soft disc the wallet stands on.
                        Container(
                          width: art * 0.86,
                          height: art * 0.86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.accent.withValues(alpha: 0.08),
                          ),
                        ),
                        WaffrMoodLogo(
                          size: art * 0.6,
                          form: page.face,
                          idle: active,
                        ),
                        _Mark(
                          icon: page.marks[0],
                          alignment: const Alignment(-0.92, -0.62),
                        ),
                        _Mark(
                          icon: page.marks[1],
                          alignment: const Alignment(0.96, -0.3),
                        ),
                        _Mark(
                          icon: page.marks[2],
                          alignment: const Alignment(-0.7, 0.86),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    page.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 15.5,
                      height: 1.7,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A small icon on a surface chip, placed around the wallet.
class _Mark extends StatelessWidget {
  final IconData icon;
  final Alignment alignment;

  const _Mark({required this.icon, required this.alignment});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: alignment,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: palette.accent),
      ),
    );
  }
}

/// Page dots; the current one stretches into a short bar.
class _Dots extends StatelessWidget {
  final int count;
  final int index;

  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      label: 'الصفحة ${index + 1} من $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.enter,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index
                    ? palette.accent
                    : palette.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}
