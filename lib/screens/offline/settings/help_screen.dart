// The help center: a way back into the interactive tutorial, a search box,
// and the questions of help_content.dart grouped by topic, each opening in
// place. Pushed from settings.

import 'package:flutter/material.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/tutorial/tutorial_controller.dart';
import 'package:waffr/screens/offline/settings/help_content.dart';
import 'package:waffr/widgets/brand/waffr_page_header.dart';
import 'package:waffr/widgets/containers/glass.dart';
import 'package:waffr/widgets/glass/aurora_backdrop.dart';

/// Text folded for search: no diacritics or tatweel, and the common letter
/// variants made equal (أ إ آ → ا, ة → ه, ى → ي), so "الإشعارات" finds
/// "الاشعارات".
String foldArabic(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

/// The entries of [sections] whose question or answer contains every word
/// of [query], with the title of their topic.
List<({String topic, HelpEntry entry})> searchHelp(
  String query,
  List<HelpSection> sections,
) {
  final words = foldArabic(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  return [
    for (final section in sections)
      for (final entry in section.items)
        if (words.every(
          foldArabic('${entry.question} ${entry.answer}').contains,
        ))
          (topic: section.title, entry: entry),
  ];
}

/// The help center page.
class HelpScreen extends StatefulWidget {
  /// Creates a [HelpScreen].
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TextEditingController _search = TextEditingController();
  final ValueNotifier<bool> _headerElevated = ValueNotifier(false);

  @override
  void dispose() {
    _search.dispose();
    _headerElevated.dispose();
    super.dispose();
  }

  /// Back to the home tab, then the tutorial from its first step.
  void _startTutorial() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    TutorialController.instance.restart();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final elevated = notification.metrics.pixels > 6;
    if (_headerElevated.value != elevated) _headerElevated.value = elevated;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: WaffrBackHeader(title: 'المساعدة', elevated: _headerElevated),
      body: AuroraPage(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (context, value, _) {
              final query = value.text.trim();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _TutorialCard(onStart: _startTutorial),
                  const SizedBox(height: 16),
                  _SearchField(controller: _search),
                  const SizedBox(height: 20),
                  if (query.isEmpty)
                    for (final section in helpSections) ...[
                      _SectionTitle(title: section.title, icon: section.icon),
                      _EntryGroup(entries: section.items),
                      const SizedBox(height: 22),
                    ]
                  else
                    ..._results(context, query),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context, String query) {
    final palette = AppPalette.of(context);
    final found = searchHelp(query, helpSections);
    if (found.isEmpty) {
      return [
        const SizedBox(height: 24),
        Icon(AppIcons.searchOff, size: 36, color: palette.textSecondary),
        const SizedBox(height: 10),
        Text(
          'لا توجد أسئلة تطابق «$query»',
          textAlign: TextAlign.center,
          style: _style(14, FontWeight.w700, palette.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'جرّب كلمة أقصر أو مختلفة، مثل «رصيد» أو «هدف».',
          textAlign: TextAlign.center,
          style: _style(12.5, FontWeight.w500, palette.textSecondary),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 5, bottom: 10),
        child: Text(
          found.length == 1 ? 'نتيجة واحدة' : 'النتائج: ${found.length}',
          style: _style(13, FontWeight.w700, palette.textSecondary),
        ),
      ),
      _EntryGroup(
        entries: [for (final item in found) item.entry],
        topics: [for (final item in found) item.topic],
        // A single result opens straight away.
        initiallyOpen: found.length == 1,
      ),
    ];
  }
}

TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: 'Outfit',
  fontFamilyFallback: const ['Tajawal'],
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// The card that starts the interactive tutorial again.
class _TutorialCard extends StatelessWidget {
  final VoidCallback onStart;

  const _TutorialCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.sparkles, color: palette.accent, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الدليل التفاعلي',
                      style: _style(16, FontWeight.w800, palette.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'جولة قصيرة تجرّب فيها أهم ميزات وفّر بنفسك، دون أن يُسجَّل شيء.',
                      style: _style(
                        12.5,
                        FontWeight.w500,
                        palette.textSecondary,
                      ).copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: onStart,
            child: Text(
              'ابدأ الدليل',
              style: _style(14.5, FontWeight.w700, palette.background),
            ),
          ),
        ],
      ),
    );
  }
}

/// The search box above the questions.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: _style(14.5, FontWeight.w500, palette.textPrimary),
      decoration: InputDecoration(
        hintText: 'ابحث في الأسئلة',
        hintStyle: _style(14, FontWeight.w500, palette.textSecondary),
        prefixIcon: Icon(AppIcons.search, color: palette.textSecondary),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                icon: Icon(AppIcons.close, color: palette.textSecondary),
                onPressed: controller.clear,
              ),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A topic heading with its icon.
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 5, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Text(title, style: _style(15, FontWeight.w800, palette.textPrimary)),
        ],
      ),
    );
  }
}

/// Questions as one card with hairlines between them, like a settings group.
class _EntryGroup extends StatelessWidget {
  final List<HelpEntry> entries;

  /// Topic of each entry, shown above its question (search results).
  final List<String>? topics;

  final bool initiallyOpen;

  const _EntryGroup({
    required this.entries,
    this.topics,
    this.initiallyOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final line = AppPalette.of(context).textSecondary.withValues(alpha: 0.12);
    return GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, thickness: 1, color: line),
                ),
              _Entry(
                key: ValueKey(entry.question),
                entry: entry,
                topic: topics?[index],
                initiallyOpen: initiallyOpen,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One question that opens in place to show its answer.
class _Entry extends StatefulWidget {
  final HelpEntry entry;
  final String? topic;
  final bool initiallyOpen;

  const _Entry({
    super.key,
    required this.entry,
    required this.topic,
    required this.initiallyOpen,
  });

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: AnimatedSize(
            duration: AppMotion.sizeOf(context, AppMotion.medium),
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.topic != null) ...[
                  Text(
                    widget.topic!,
                    style: _style(11.5, FontWeight.w700, palette.accent),
                  ),
                  const SizedBox(height: 3),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.entry.question,
                        style: _style(
                          14.5,
                          FontWeight.w700,
                          palette.textPrimary,
                        ).copyWith(height: 1.4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.medium),
                      child: Icon(
                        AppIcons.chevronDown,
                        size: 20,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.entry.answer,
                    style: _style(
                      13.5,
                      FontWeight.w400,
                      palette.textSecondary,
                    ).copyWith(height: 1.65),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
