// Home card chrome shared by every dashboard section (part of
// dashboard.dart): the card frame, its title row, the header link, the
// empty state and the text style helper.

part of 'dashboard.dart';

/// The app's text style at [size]: Outfit with Tajawal for Arabic.
/// [tabular] gives digits one width, so amounts line up and do not jitter
/// while they roll.
TextStyle _text(
  double size, {
  FontWeight weight = FontWeight.w400,
  required Color color,
  bool tabular = false,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: const ['Tajawal'],
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// Shared card shell used by the dashboard sections. With [onTap] the
/// whole card is pressable and opens the screen with the full details.
class _SectionCard extends StatelessWidget {
  final String title;

  /// A link-style hint at the end of the title row ("show all").
  final String? action;

  final Widget child;
  final VoidCallback? onTap;

  /// A narrower card that shares its row with another: a little less
  /// padding and a smaller title.
  final bool compact;

  const _SectionCard({
    required this.title,
    required this.child,
    this.action,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final card = GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: compact
          ? const EdgeInsets.fromLTRB(15, 15, 15, 9)
          : const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    compact ? 15.5 : 16.5,
                    weight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (action != null) _HeaderLink(label: action!),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          child,
          const SizedBox(height: 6),
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: Pressable(onTap: onTap, depth: 0.02, child: card),
    );
  }
}

/// Two cards side by side, the same height: the [wide] one on the start
/// side (the right, in Arabic) takes two thirds of the row.
class _CardPair extends StatelessWidget {
  final Widget wide;
  final Widget narrow;

  const _CardPair({required this.wide, required this.narrow});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: wide),
          const SizedBox(width: kCardGap),
          Expanded(child: narrow),
        ],
      ),
    );
  }
}

/// "Show all" at the end of a section header; the card around it takes
/// the tap.
class _HeaderLink extends StatelessWidget {
  final String label;

  const _HeaderLink({required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: _text(12.5, weight: FontWeight.w600, color: palette.accent),
          ),
          const SizedBox(width: 2),
          Icon(AppIcons.chevronForward, size: 15, color: palette.accent),
        ],
      ),
    );
  }
}

/// Icon and one line for a section with nothing to show yet.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  /// Smaller mark and text, for a card that shares its row.
  final bool compact;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 44,
            height: compact ? 38 : 44,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: compact ? 18 : 21, color: palette.accent),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Text(
              message,
              style: _text(compact ? 12.5 : 13.5, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
