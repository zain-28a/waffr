// Obligation edit sheet (part of obligations_sheet.dart): change what a
// recurring expense is called, its category, how often it repeats and the
// date of its next charge.

part of 'obligations_sheet.dart';

/// Opens the editor for the obligation with [id].
Future<void> showEditObligationSheet(BuildContext context, String id) {
  final item = RecurringExpenseStore.instance.byId(id);
  if (item == null) return Future<void>.value();
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _EditObligationSheet(item: item),
  );
}

class _EditObligationSheet extends StatefulWidget {
  final RecurringExpense item;

  const _EditObligationSheet({required this.item});

  @override
  State<_EditObligationSheet> createState() => _EditObligationSheetState();
}

class _EditObligationSheetState extends State<_EditObligationSheet> {
  static const int _maxInterval = 99;

  late final RecurringExpense _original = widget.item;
  late final TextEditingController _name = TextEditingController(
    text: _original.note ?? '',
  );
  late String _category = categoryFor(_original.category).label;
  late RecurringUnit _unit = _original.unit;
  late int _count = _original.intervalCount;
  late DateTime _next = _original.nextDueAt;
  bool _saving = false;

  bool get _changed =>
      _name.text.trim() != (_original.note ?? '').trim() ||
      _category != categoryFor(_original.category).label ||
      _unit != _original.unit ||
      _count != _original.intervalCount ||
      _next != _original.nextDueAt;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickNext() async {
    final now = deviceNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showWaffrDatePicker(
      context: context,
      title: 'موعد الدفعة القادمة',
      firstDate: today,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      initialDate: _next.isBefore(today) ? today : _next,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _next = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _next.hour,
        _next.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_changed || _saving) return;
    setState(() => _saving = true);
    final saved = await RecurringExpenseStore.instance.updateDetails(
      _original.id,
      note: _name.text,
      category: _category,
      unit: _unit,
      intervalCount: _count,
      nextDueAt: _next != _original.nextDueAt ? _next : null,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      AppHaptics.warning();
      return;
    }
    AppHaptics.success();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ObligationColors.of(context);

    return GlassSheetBody(
      children: [
        const GlassSheetHeader(
          title: 'تعديل الالتزام',
          subtitle: 'الدفعات المسجّلة سابقاً لا تتغيّر.',
        ),
        const SizedBox(height: 16),
        const SheetFieldLabel(text: 'الاسم', optional: true),
        SheetTextField(
          controller: _name,
          hint: 'مثال: إيجار، اشتراك الإنترنت...',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const SheetFieldLabel(text: 'التصنيف'),
        ExpenseCategoryGrid(
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 14),
        const SheetFieldLabel(text: 'التكرار'),
        SheetChoiceChips(
          options: [for (final unit in RecurringUnit.values) unit.label],
          selected: _unit.label,
          onSelected: (value) => setState(() {
            _unit = RecurringUnit.values.firstWhere((u) => u.label == value);
          }),
        ),
        const SizedBox(height: 10),
        // Every how many units: a small stepper.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: sheetFieldColor(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              SheetCircleButton(
                icon: AppIcons.remove,
                onTap: () {
                  if (_count <= 1) return;
                  AppHaptics.selection();
                  setState(() => _count--);
                },
              ),
              Expanded(
                child: Text(
                  _count <= 1
                      ? 'كل ${_unit.label}'
                      : 'كل $_count ${_unit.plural}',
                  textAlign: TextAlign.center,
                  style: _text(
                    colors.textPrimary,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              SheetCircleButton(
                icon: AppIcons.add,
                onTap: () {
                  if (_count >= _maxInterval) return;
                  AppHaptics.selection();
                  setState(() => _count++);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SheetFieldLabel(text: 'الدفعة القادمة'),
        Material(
          color: sheetFieldColor(context),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _pickNext,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(AppIcons.calendar, size: 19, color: colors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_next.day} ${CalendarPeriod.monthName(_next.month)} '
                      '${_next.year}',
                      style: _text(
                        colors.textPrimary,
                        size: 15,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    AppIcons.chevronDown,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SheetSaveButton(
          label: 'حفظ التعديلات',
          enabled: _changed && !_saving,
          onTap: _save,
        ),
      ],
    );
  }
}
