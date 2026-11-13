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

  /// A figure at the end of the title row, with its small caption.
  final String? trailing;
  final String? trailingCaption;
  final Widget child;
  final VoidCallback? onTap;

  const _SectionCard({
    required this.title,
    required this.child,
    this.action,
    this.trailing,
    this.trailingCaption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final card = GlassContainer(
      colorType: GlassColorType.surface,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
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
                    16.5,
                    weight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (trailing != null)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: trailing,
                        style: _text(
                          15.5,
                          weight: FontWeight.w700,
                          color: palette.accent,
                          tabular: true,
                        ),
                      ),
                      if (trailingCaption != null)
                        TextSpan(
                          text: ' $trailingCaption',
                          style: _text(11.5, color: palette.textSecondary),
                        ),
                    ],
                  ),
                ),
              if (action != null) _HeaderLink(label: action!),
            ],
          ),
          const SizedBox(height: 10),
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

/// "Show all" at the end of a section header. Tappable on its own when
/// [onTap] is set; otherwise the card around it takes the tap.
class _HeaderLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _HeaderLink({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final link = Padding(
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
    if (onTap == null) return link;
    return Pressable(onTap: onTap, depth: 0.06, child: link);
  }
}

/// Icon and one line for a section with nothing to show yet.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: _text(13.5, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
