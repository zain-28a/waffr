// Saved-expense box opened from the star on the expense sheet. Same frame as
// the custom-category box: a grid of tiles plus Cancel / Add actions.

import 'package:flutter/material.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/app_feedback.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/data/models/expense_categories.dart';
import 'package:waffer/data/models/expense_preset.dart';
import 'package:waffer/data/stores/expense_preset_store.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

/// What the user chose in the box.
sealed class ExpensePresetChoice {
  const ExpensePresetChoice();
}

/// "إضافة": save the expense being entered as a preset when it is saved.
class ExpensePresetMark extends ExpensePresetChoice {
  const ExpensePresetMark();
}

/// The star was already filled and the user no longer wants to save it.
class ExpensePresetUnmark extends ExpensePresetChoice {
  const ExpensePresetUnmark();
}

/// Fill the expense form from [preset].
class ExpensePresetSelected extends ExpensePresetChoice {
  final ExpensePreset preset;

  const ExpensePresetSelected(this.preset);
}

Future<ExpensePresetChoice?> showExpensePresetsDialog(
  BuildContext context, {
  required bool marked,
}) {
  return showAppDialog<ExpensePresetChoice>(
    context: context,
    builder: (_) => _ExpensePresetsDialog(marked: marked),
  );
}

class _ExpensePresetsDialog extends StatefulWidget {
  final bool marked;

  const _ExpensePresetsDialog({required this.marked});

  @override
  State<_ExpensePresetsDialog> createState() => _ExpensePresetsDialogState();
}

class _ExpensePresetsDialogState extends State<_ExpensePresetsDialog> {
  final ExpensePresetStore _store = ExpensePresetStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  Future<void> _delete(ExpensePreset preset) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف المصروف المحفوظ',
      message: 'سيُحذف "${_titleOf(preset)}" من المصاريف المحفوظة. '
          'المصاريف المسجّلة لا تتأثر.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _store.remove(preset.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: size.width > 460 ? 400 : size.width - 40,
        constraints: BoxConstraints(maxHeight: size.height * 0.72),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Text(
                    'المصاريف المحفوظة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontFamilyFallback: const ['Tajawal'],
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  child: SheetCircleButton(
                    icon: Icons.info_outline_rounded,
                    onTap: () => _showHelp(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListenableBuilder(
                listenable: _store,
                builder: (context, _) {
                  final presets = _store.items;
                  if (presets.isEmpty) {
                    return _EmptyPresets(color: textSecondary);
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    itemCount: presets.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 0.92,
                    ),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return _PresetTile(
                        key: ValueKey(preset.id),
                        preset: preset,
                        onTap: () => Navigator.of(context).pop(
                          ExpensePresetSelected(preset),
                        ),
                        onLongPress: () => _delete(preset),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: ['Tajawal'],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      widget.marked
                          ? const ExpensePresetUnmark()
                          : const ExpensePresetMark(),
                    ),
                    child: Text(
                      widget.marked ? 'إلغاء الإضافة' : 'إضافة',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// What the star does, in plain Arabic, opened from the (i) button.
Future<void> _showHelp(BuildContext context) {
  return showAppInfoDialog(
    context,
    title: 'ما هي المصاريف المحفوظة؟',
    message: 'المصاريف المحفوظة توفّر عليك إعادة كتابة المصاريف التي تتكرر '
        'عندك، مثل الخبز أو أجرة المواصلات.\n\n'
        'لحفظ مصروف: أدخل المبلغ والتصنيف والملاحظة كالمعتاد، ثم اضغط النجمة '
        'واختر "إضافة". تصبح النجمة خضراء، وعند الضغط على "حفظ المصروف" يُسجَّل '
        'المصروف ويُحفظ معه نسخة هنا.\n\n'
        'لاستخدام مصروف محفوظ: اضغط النجمة واختر البطاقة المناسبة، فتُملأ '
        'الحقول تلقائياً، ويمكنك تعديلها قبل الحفظ.\n\n'
        'لحذف مصروف محفوظ: اضغط على بطاقته مطولاً. حذفه لا يؤثر على '
        'المصاريف المسجّلة سابقاً.',
    actionLabel: 'فهمت',
  );
}

String _titleOf(ExpensePreset preset) {
  final note = preset.note?.trim();
  return note == null || note.isEmpty ? preset.category : note;
}

class _EmptyPresets extends StatelessWidget {
  final Color color;

  const _EmptyPresets({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_border_rounded,
            size: 34,
            color: color.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 8),
          Text(
            'لا توجد مصاريف محفوظة بعد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontFamilyFallback: const ['Tajawal'],
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Category tile shape from the expense grid, with the item name under it.
class _PresetTile extends StatelessWidget {
  final ExpensePreset preset;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PresetTile({
    super.key,
    required this.preset,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final category = categoryFor(preset.category);
    final note = preset.note?.trim() ?? '';

    return Material(
      color: sheetFieldColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, size: 18, color: accent),
              const SizedBox(height: 4),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontFamilyFallback: const ['Tajawal'],
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note.isEmpty ? 'بدون ملاحظة' : note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontFamilyFallback: const ['Tajawal'],
                  fontSize: 10.5,
                  color: textSecondary.withValues(
                    alpha: note.isEmpty ? 0.6 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${formatMoney(preset.total)} '
                  '${currencyLabelFor(preset.currencyCode)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontFamilyFallback: const ['Tajawal'],
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
