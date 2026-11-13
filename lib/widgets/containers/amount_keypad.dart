// Waffr's number pad for amounts: quick amounts the user can edit, the ten
// digits, delete and done. Inside a glass sheet it docks at the bottom of
// the screen, where a keyboard would be; elsewhere it opens under the field.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffr/core/prefs/app_prefs.dart';
import 'package:waffr/core/theme/app_icons.dart';
import 'package:waffr/core/theme/app_motion.dart';
import 'package:waffr/core/theme/app_palette.dart';
import 'package:waffr/core/utils/app_feedback.dart';
import 'package:waffr/core/utils/money.dart';
import 'package:waffr/widgets/motion/pressable.dart';

/// The round amounts offered above the keys. They start as the Syrian
/// banknote values and the user can change them; the choice is kept in
/// prefs.
class QuickAmounts extends ChangeNotifier {
  QuickAmounts._();

  /// The app-wide list.
  static final QuickAmounts instance = QuickAmounts._();

  /// The amounts a fresh install starts with.
  static const List<int> defaults = [10, 25, 50, 100, 200, 500];

  /// Most amounts the row can hold.
  static const int maxCount = 6;

  /// Largest amount accepted.
  static const int maxValue = 999999999;

  static const String _key = 'quick_amounts';

  List<int> _values = defaults;
  Future<void>? _loader;

  /// The amounts, smallest first.
  List<int> get values => List.unmodifiable(_values);

  /// True while the list is still the default one.
  bool get isDefault =>
      _values.length == defaults.length &&
      List.generate(
        defaults.length,
        (i) => _values[i] == defaults[i],
      ).every((same) => same);

  /// Reads the stored list once; later calls return the same future.
  Future<void> ensureLoaded() => _loader ??= _load();

  Future<void> _load() async {
    final prefs = await AppPrefs.instance;
    final stored = prefs.getStringList(_key);
    if (stored == null) return;
    final parsed = _clean(stored.map(int.tryParse).whereType<int>());
    if (parsed.isEmpty) return;
    _values = parsed;
    notifyListeners();
  }

  /// Valid, unique amounts in rising order, at most [maxCount].
  static List<int> _clean(Iterable<int> raw) {
    final unique = raw.where((v) => v > 0 && v <= maxValue).toSet().toList()
      ..sort();
    return unique.take(maxCount).toList(growable: false);
  }

  /// Adds [value]; false when it is invalid, a duplicate, or the row is full.
  Future<bool> add(int value) async {
    if (value <= 0 || value > maxValue) return false;
    if (_values.contains(value) || _values.length >= maxCount) return false;
    await _save([..._values, value]);
    return true;
  }

  /// Removes [value].
  Future<void> remove(int value) =>
      _save(_values.where((v) => v != value).toList());

  /// Back to [defaults].
  Future<void> reset() => _save(defaults);

  Future<void> _save(List<int> next) async {
    _loader ??= Future<void>.value();
    _values = _clean(next);
    notifyListeners();
    final prefs = await AppPrefs.instance;
    await prefs.setStringList(_key, [for (final v in _values) '$v']);
  }

  /// Forgets the in-memory list so the next read comes from prefs (tests).
  @visibleForTesting
  void resetCache() {
    _values = defaults;
    _loader = null;
  }
}

/// What the keypad does to the amount field that owns it.
@immutable
class AmountKeypadBinding {
  /// Appends a digit.
  final ValueChanged<String> onKey;

  /// Deletes the last digit.
  final VoidCallback onBackspace;

  /// Clears the amount (long press on delete).
  final VoidCallback onClear;

  /// Adds a quick amount to what is typed.
  final ValueChanged<int> onAdd;

  /// Closes the keypad.
  final VoidCallback onDone;

  /// Opens the quick-amounts editor.
  final VoidCallback onEditQuick;

  /// A binding.
  const AmountKeypadBinding({
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onAdd,
    required this.onDone,
    required this.onEditQuick,
  });
}

/// Holds the amount field that currently owns the docked keypad, if any.
class AmountKeypadController extends ChangeNotifier {
  AmountKeypadBinding? _binding;

  /// The field the keypad types into, or null while it is closed.
  AmountKeypadBinding? get binding => _binding;

  /// Opens the keypad for [binding].
  void attach(AmountKeypadBinding binding) {
    if (identical(_binding, binding)) return;
    _binding = binding;
    notifyListeners();
  }

  /// Closes the keypad if [binding] still owns it.
  void detach(AmountKeypadBinding binding) {
    if (!identical(_binding, binding)) return;
    _binding = null;
    notifyListeners();
  }
}

/// Lets amount fields below find the surface that docks their keypad.
class AmountKeypadScope extends InheritedWidget {
  /// The dock's controller.
  final AmountKeypadController controller;

  /// Creates an [AmountKeypadScope].
  const AmountKeypadScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The nearest dock, or null when the field is not inside one.
  static AmountKeypadController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AmountKeypadScope>()?.controller;

  @override
  bool updateShouldNotify(AmountKeypadScope oldWidget) =>
      oldWidget.controller != controller;
}

/// The number pad itself. Digits are always laid out left to right, as on
/// a phone dialer, whatever the reading direction.
class AmountKeypad extends StatefulWidget {
  /// The field it types into.
  final AmountKeypadBinding binding;

  /// Creates an [AmountKeypad].
  const AmountKeypad({super.key, required this.binding});

  /// Height of the pad without outer padding.
  static const double height = 36 + 4 * (48 + _gap);

  static const double _gap = 8;

  @override
  State<AmountKeypad> createState() => _AmountKeypadState();
}

class _AmountKeypadState extends State<AmountKeypad> {
  @override
  void initState() {
    super.initState();
    QuickAmounts.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final binding = widget.binding;

    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.only(top: AmountKeypad._gap),
      child: Row(
        children: [
          for (final (index, key) in keys.indexed) ...[
            if (index > 0) const SizedBox(width: AmountKeypad._gap),
            Expanded(child: key),
          ],
        ],
      ),
    );

    Widget digit(String value) => _KeypadKey(
      label: value,
      semantics: value,
      onTap: () => binding.onKey(value),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick amounts, then the button that edits them.
          ListenableBuilder(
            listenable: QuickAmounts.instance,
            builder: (context, _) {
              final amounts = QuickAmounts.instance.values;
              return Row(
                children: [
                  for (final amount in amounts) ...[
                    Expanded(
                      child: _KeypadKey(
                        label: '+${formatMoney(amount)}',
                        semantics: 'إضافة ${formatMoney(amount)}',
                        height: 36,
                        fontSize: 13,
                        tinted: true,
                        onTap: () => binding.onAdd(amount),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  SizedBox(
                    width: 40,
                    child: _KeypadKey(
                      icon: AppIcons.edit,
                      iconSize: 17,
                      semantics: 'تعديل المبالغ السريعة',
                      height: 36,
                      onTap: binding.onEditQuick,
                    ),
                  ),
                ],
              );
            },
          ),
          row([digit('1'), digit('2'), digit('3')]),
          row([digit('4'), digit('5'), digit('6')]),
          row([digit('7'), digit('8'), digit('9')]),
          row([
            _KeypadKey(
              icon: AppIcons.backspace,
              semantics: 'حذف',
              onTap: binding.onBackspace,
              onLongPress: binding.onClear,
            ),
            digit('0'),
            _KeypadKey(
              icon: AppIcons.check,
              semantics: 'تم',
              color: palette.accent,
              foreground: palette.onAccent,
              onTap: binding.onDone,
            ),
          ]),
        ],
      ),
    );
  }
}

/// One key: it sinks under the finger and springs back.
class _KeypadKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final double iconSize;
  final String semantics;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double height;
  final double fontSize;

  /// A soft accent tint, for the quick amounts.
  final bool tinted;

  /// Fill and content colors of a filled key (done).
  final Color? color;
  final Color? foreground;

  const _KeypadKey({
    required this.semantics,
    required this.onTap,
    this.label,
    this.icon,
    this.iconSize = 22,
    this.onLongPress,
    this.height = 48,
    this.fontSize = 21,
    this.tinted = false,
    this.color,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        color ??
        (tinted
            ? palette.accent.withValues(alpha: 0.12)
            : palette.surface.withValues(alpha: isDark ? 0.5 : 0.9));
    final ink = foreground ?? (tinted ? palette.accent : palette.textPrimary);

    return Semantics(
      button: true,
      label: semantics,
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        // The field fires the haptic once the edit is accepted.
        haptic: false,
        depth: 0.08,
        child: ExcludeSemantics(
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(height / 2.6),
            ),
            child: icon != null
                ? Icon(icon, size: iconSize, color: ink)
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label!,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontFamilyFallback: const ['Tajawal'],
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Opens the editor for the quick amounts: remove any, add a new one (up to
/// six), or go back to the default banknote values.
Future<void> showQuickAmountsEditor(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (context) => const _QuickAmountsDialog(),
  );
}

class _QuickAmountsDialog extends StatefulWidget {
  const _QuickAmountsDialog();

  @override
  State<_QuickAmountsDialog> createState() => _QuickAmountsDialogState();
}

class _QuickAmountsDialogState extends State<_QuickAmountsDialog> {
  final TextEditingController _input = TextEditingController();
  final QuickAmounts _store = QuickAmounts.instance;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = int.tryParse(_input.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (value == null || value <= 0) return;
    final added = await _store.add(value);
    if (!mounted) return;
    if (added) {
      AppHaptics.success();
      _input.clear();
    } else {
      AppHaptics.warning();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final style = TextStyle(
      fontFamily: 'Outfit',
      fontFamilyFallback: const ['Tajawal'],
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: palette.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final values = _store.values;
        final full = values.length >= QuickAmounts.maxCount;
        return AppDialogFrame(
          title: 'المبالغ السريعة',
          message: 'تظهر فوق لوحة الأرقام وتُضاف إلى المبلغ بضغطة واحدة.',
          kind: AppFeedbackKind.info,
          actions: [
            AppDialogAction(
              label: 'الافتراضية',
              enabled: !_store.isDefault,
              onPressed: () {
                AppHaptics.selection();
                _store.reset();
              },
            ),
            AppDialogAction(
              label: 'تم',
              primary: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in values)
                    Semantics(
                      button: true,
                      label: 'حذف ${formatMoney(value)}',
                      child: Pressable(
                        onTap: () => _store.remove(value),
                        depth: 0.06,
                        child: ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              12,
                              7,
                              8,
                              7,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(formatMoney(value), style: style),
                                const SizedBox(width: 6),
                                Icon(
                                  AppIcons.close,
                                  size: 14,
                                  color: palette.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !full,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      onSubmitted: (_) => _add(),
                      textAlign: TextAlign.center,
                      style: style.copyWith(fontSize: 16),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: palette.textSecondary.withValues(alpha: 0.1),
                        hintText: full
                            ? 'احذف مبلغاً لإضافة غيره'
                            : 'مبلغ جديد',
                        hintStyle: style.copyWith(
                          fontWeight: FontWeight.w400,
                          color: palette.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'إضافة المبلغ',
                    child: Pressable(
                      onTap: full ? null : _add,
                      depth: 0.08,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(
                              alpha: full ? 0.3 : 1,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            AppIcons.add,
                            size: 22,
                            color: palette.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
