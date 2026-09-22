import 'package:flutter/material.dart';
import 'package:waffer/core/data/currency.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/widgets/containers/glass_sheet.dart';

Future<void> showCurrenciesSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _CurrenciesSheet(),
  );
}

class _CurrenciesSheet extends StatefulWidget {
  const _CurrenciesSheet();

  @override
  State<_CurrenciesSheet> createState() => _CurrenciesSheetState();
}

class _CurrenciesSheetState extends State<_CurrenciesSheet> {
  final CurrencyStore _store = CurrencyStore.instance;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  Future<void> _add(CurrencyInfo item) async {
    final added = await _store.addCurrency(item.code);
    if (!added || !mounted) return;
    setState(() => _adding = false);
  }

  Future<void> _remove(CurrencyInfo item) async {
    if (item.code == defaultCurrencyCode) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إخفاء العملة'),
          content: Text(
            'ستُخفى ${item.arabicName} من القائمة. السجل المالي الخاص بها يبقى محفوظاً ويمكن استعادته لاحقاً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'إخفاء',
                style: TextStyle(
                  color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    await _store.removeCurrency(item.code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final enabled = _store.enabledCurrencies;
        final available = _store.availableToAdd;

        return GlassSheetBody(
          children: [
            const GlassSheetHeader(
              title: 'العملات',
              subtitle: 'أضف عملة مستقلة أو اختر العملة النشطة.',
            ),
            const SizedBox(height: 16),
            for (final item in enabled) ...[
              _CurrencyTile(
                item: item,
                active: item.code == _store.activeCode,
                canRemove: item.code != defaultCurrencyCode,
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onTap: () => _store.setActive(item.code),
                onRemove: () => _remove(item),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            if (available.isNotEmpty)
              SheetSaveButton(
                label: _adding ? 'اختر العملة' : 'إضافة عملة',
                onTap: () => setState(() => _adding = !_adding),
              ),
            SheetExpand(
              visible: _adding && available.isNotEmpty,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    for (final item in available) ...[
                      Material(
                        color: sheetFieldColor(context),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _add(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 42,
                                  child: Text(
                                    item.symbol,
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${item.arabicName} · ${item.code}',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.add_rounded,
                                  color: accent,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  final CurrencyInfo item;
  final bool active;
  final bool canRemove;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _CurrencyTile({
    required this.item,
    required this.active,
    required this.canRemove,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: sheetFieldColor(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  item.symbol,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.arabicName,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      active ? '${item.code} · نشطة' : item.code,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: active ? accent : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: textSecondary.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
