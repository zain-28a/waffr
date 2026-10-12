// Transaction history chrome: the share-format dialog and the
// multi-select bar and marks.

part of 'reportscreen.dart';

enum _ExpenseShareFormat { pdf, text }

class _ShareFormatDialog extends StatelessWidget {
  const _ShareFormatDialog();

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      title: 'مشاركة السجل',
      message: 'اختر طريقة تصدير المصروفات المحددة.',
      kind: AppFeedbackKind.info,
      child: Row(
        children: [
          Expanded(
            child: _FormatChoice(
              label: 'PDF',
              icon: Icons.picture_as_pdf_outlined,
              onTap: () => Navigator.pop(context, _ExpenseShareFormat.pdf),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FormatChoice(
              label: 'نص',
              icon: Icons.notes_rounded,
              onTap: () => Navigator.pop(context, _ExpenseShareFormat.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FormatChoice({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return GlassButton(
      onTap: onTap,
      colorType: GlassColorType.surface,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onPickRange;

  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onToggleAll,
    required this.onPickRange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'إلغاء',
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: colors.textPrimary),
            ),
            _SelectMark(
              state: allSelected ? _SelectState.checked : _SelectState.empty,
              onTap: onToggleAll,
            ),
            const SizedBox(width: 10),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontFamilyFallback: const ['Tajawal'],
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'نطاق التاريخ',
              onPressed: onPickRange,
              icon: Icon(
                Icons.calendar_month_outlined,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SelectState { empty, partial, checked }

class _SelectMark extends StatelessWidget {
  final _SelectState state;
  final VoidCallback onTap;

  const _SelectMark({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final checked = state == _SelectState.checked;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? colors.accent : Colors.transparent,
          border: Border.all(
            color: checked ? colors.accent : colors.textSecondary,
            width: 1.6,
          ),
        ),
        child: state == _SelectState.checked
            ? Icon(Icons.check_rounded, size: 14, color: colors.onAccent)
            : state == _SelectState.partial
            ? Container(width: 10, height: 2, color: colors.accent)
            : null,
      ),
    );
  }
}
