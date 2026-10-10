// Pick the active currency or add/hide additional currencies.

import 'package:flutter/material.dart';
import 'package:waffr/widgets/button/app_primary_button.dart';
import 'package:waffr/widgets/containers/app_empty_state.dart';
import 'package:waffr/data/stores/currency_store.dart';
import 'package:waffr/core/theme/app_color.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/widgets/containers/glass_sheet.dart';

Future<void> showCurrenciesSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _CurrenciesSheet(),
  );
}

// Currencies list UI driven by CurrencyStore.
class _CurrenciesSheet extends StatefulWidget {
  const _CurrenciesSheet();

  @override
  State<_CurrenciesSheet> createState() => _CurrenciesSheetState();
}

class _CurrenciesSheetState extends State<_CurrenciesSheet> {
  final CurrencyStore _store = CurrencyStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  // Hides a non-default currency from the picker; its ledger stays intact.
  Future<void> _remove(CurrencyInfo item) async {
    if (item.code == defaultCurrencyCode) return;

    final confirm = await showAppConfirmDialog(
      context,
      title: 'إخفاء العملة',
      message:
          'ستُخفى ${item.arabicName} من القائمة. السجل المالي الخاص بها يبقى محفوظاً ويمكن استعادته لاحقاً.',
      confirmLabel: 'إخفاء',
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
              AppPrimaryButton(
                label: 'إضافة عملة',
                icon: Icons.add_rounded,
                onTap: () => showAddCurrencySheet(context),
              ),
          ],
        );
      },
    );
  }
}

/// Picker stacked on the currencies sheet. Choosing one adds it and closes.
Future<void> showAddCurrencySheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    builder: (context) => const _AddCurrencySheet(),
  );
}

class _AddCurrencySheet extends StatelessWidget {
  const _AddCurrencySheet();

  @override
  Widget build(BuildContext context) {
    final store = CurrencyStore.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final available = store.availableToAdd;
        return GlassSheetBody(
          children: [
            const GlassSheetHeader(
              title: 'إضافة عملة',
              subtitle: 'اختر عملة لتظهر في قائمة المبالغ.',
            ),
            const SizedBox(height: 16),
            if (available.isEmpty)
              const AppEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'كل العملات المتاحة مضافة',
              )
            else
              for (final item in available) ...[
                Material(
                  color: sheetFieldColor(context),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final added = await store.addCurrency(item.code);
                      if (!added || !context.mounted) return;
                      Navigator.of(context).maybePop();
                    },
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
                                fontFamily: 'Outfit',
                                fontFamilyFallback: ['Tajawal'],
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
                                fontFamily: 'Outfit',
                                fontFamilyFallback: ['Tajawal'],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          Icon(Icons.add_rounded, color: accent, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

// One enabled currency with active highlight and optional hide action.
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
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      active ? '${item.code} · نشطة' : item.code,
                      style: TextStyle(
                        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
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
