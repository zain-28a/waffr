// Shared bottom-sheet toolkit: open a glass sheet, lay out its body, and reuse
// the same field / chrome helpers so new sheets look and behave the same.
//
// The modal barrier is a flat dim ([kSheetBarrierColor]), not a BackdropFilter
// blur — live blur behind the sheet was too expensive. The sheet itself is a
// translucent GlassContainer fill, same performance choice as glass cards.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waffer/data/stores/currency_store.dart';
import 'package:waffer/core/theme/app_color.dart';
import 'package:waffer/core/utils/money.dart';
import 'package:waffer/widgets/containers/glass.dart';

/// Modal barrier tint. Dims the page behind the sheet without blurring it.
const Color kSheetBarrierColor = Color.fromARGB(114, 0, 0, 0);

/// Opens a transparent modal bottom sheet wrapped in [_GlassSheetShell].
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: kSheetBarrierColor,
    elevation: 0,
    builder: (context) => _GlassSheetShell(
      builder: builder,
      heightFactor: heightFactor,
    ),
  );
}

/// Positions the sheet above the keyboard and optionally pins its height.
class _GlassSheetShell extends StatelessWidget {
  final WidgetBuilder builder;
  final double? heightFactor;

  const _GlassSheetShell({
    required this.builder,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final maxSheetHeight =
        (screenHeight - keyboard - 28).clamp(220.0, screenHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: heightFactor == null
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: builder(context),
            )
          : SizedBox(
              height: (screenHeight * heightFactor!).clamp(220.0, maxSheetHeight),
              child: builder(context),
            ),
    );
  }
}

/// Fixed-height layout: pinned header, scrollable [body] below.
class GlassSheetFixedBody extends StatelessWidget {
  final Widget header;
  final Widget body;

  const GlassSheetFixedBody({
    super.key,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: GlassContainer(
        colorType: GlassColorType.surface,
        tintOpacity: 1,
        radius: const BorderRadius.vertical(top: Radius.circular(34)),
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: header,
              ),
              const SizedBox(height: 8),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Default sheet shell: large top corners and a single scrollable column.
class GlassSheetBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const GlassSheetBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      colorType: GlassColorType.surface,
      tintOpacity: 1,
      radius: const BorderRadius.vertical(top: Radius.circular(34)),
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: padding,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle, title, subtitle, close, and optional next control.
class GlassSheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onNext;

  const GlassSheetHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: textSecondary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 18),
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              child: SheetCircleButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (onNext != null)
              Positioned(
                right: 0,
                child: SheetCircleButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNext!,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Round icon button used in sheet headers (close / next).
class SheetCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const SheetCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Material(
      color: sheetFieldColor(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 22,
            color: textPrimary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// Small label above a field; can mark the field optional and host a trailing action.
class SheetFieldLabel extends StatelessWidget {
  final String text;
  final bool optional;
  final Widget? action;

  const SheetFieldLabel({
    super.key,
    required this.text,
    this.optional = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textSecondary,
            ),
          ),
          
          if (optional)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Text(
                ' (اختياري)',
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 11,
                  color: textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Which inline menu under the amount row is open.
enum _AmountMenu { none, currency, multiplier }

/// Large centered amount entry with currency selector and optional helper text.
/// New money sheets should reuse this instead of rolling a custom amount row.
///
/// Currency and the × multiplier open a scrollable list over the sheet,
/// narrower than the sheet, dropping down from the control that was tapped.
class SheetAmountField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? helper;
  final ValueChanged<String>? onChanged;

  /// Optional widget in the left slot when there is no [onMultiplierChanged].
  final Widget? leading;

  /// Displayed currency; defaults to the home-screen active currency.
  final String? currencyCode;
  final ValueChanged<String>? onCurrencyChanged;

  /// When set, the left slot is ×1–×10 and opens the same downward list.
  final int? multiplier;
  final ValueChanged<int>? onMultiplierChanged;

  const SheetAmountField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.onChanged,
    this.leading,
    this.currencyCode,
    this.onCurrencyChanged,
    this.multiplier,
    this.onMultiplierChanged,
  });

  @override
  State<SheetAmountField> createState() => _SheetAmountFieldState();
}

class _SheetAmountFieldState extends State<SheetAmountField> {
  static const List<int> _multipliers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  final GlobalKey _currencyKey = GlobalKey();
  final GlobalKey _multiplierKey = GlobalKey();

  _AmountMenu _menu = _AmountMenu.none;
  OverlayEntry? _entry;

  String get _code {
    return Currencies.normalize(
      widget.currencyCode ?? CurrencyStore.instance.activeCode,
    );
  }

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _close() {
    _removeEntry();
    if (_menu == _AmountMenu.none || !mounted) return;
    setState(() => _menu = _AmountMenu.none);
  }

  void _toggle(_AmountMenu menu) {
    if (_menu == menu) {
      _close();
      return;
    }
    _removeEntry();
    setState(() => _menu = menu);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu == menu) _showMenu(menu);
    });
  }

  /// Drops a scrollable list over the sheet, narrower than the sheet itself.
  void _showMenu(_AmountMenu menu) {
    final anchorKey = menu == _AmountMenu.currency ? _currencyKey : _multiplierKey;
    final anchor = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchor == null || !anchor.hasSize) return;

    final origin = anchor.localToGlobal(Offset.zero);
    final anchorSize = anchor.size;
    final screen = MediaQuery.sizeOf(context);
    final isMultiplier = menu == _AmountMenu.multiplier;
    // ×1–×10 is a short label; keep that list a tight column on the button.
    final menuWidth = isMultiplier
        ? 64.0
        : (screen.width * 0.62).clamp(180.0, 260.0);
    var left = isMultiplier
        ? origin.dx + (anchorSize.width - menuWidth) / 2
        : origin.dx;
    left = left.clamp(16.0, screen.width - menuWidth - 16);
    final top = origin.dy + anchorSize.height + 6;
    final maxHeight = (screen.height - top - 16).clamp(120.0, 220.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    final tiles = menu == _AmountMenu.currency
        ? [
            for (final item in CurrencyStore.instance.enabledCurrencies)
              _AmountMenuTile(
                title: item.arabicName,
                leading: item.symbol,
                selected: item.code == _code,
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onTap: () {
                  widget.onCurrencyChanged?.call(item.code);
                  _close();
                },
              ),
          ]
        : [
            for (final value in _multipliers)
              _AmountMenuTile(
                title: '×$value',
                centered: true,
                selected: value == (widget.multiplier ?? 1),
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                onTap: () {
                  widget.onMultiplierChanged?.call(value);
                  _close();
                },
              ),
          ];

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: _AmountMenuDrop(
                child: Material(
                  color: surface,
                  elevation: 10,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: tiles,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return ListenableBuilder(
      listenable: CurrencyStore.instance,
      builder: (context, _) {
        final options = CurrencyStore.instance.enabledCurrencies;
        final selectable =
            widget.onCurrencyChanged != null && options.length > 1;
        final showMultiplier = widget.onMultiplierChanged != null;
        final symbol = Currencies.symbolOf(_code);

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: sheetFieldColor(context),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 13,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    key: _multiplierKey,
                    width: 46,
                    child: showMultiplier
                        ? _AmountSlotButton(
                            label: '×${widget.multiplier ?? 1}',
                            color: textSecondary,
                            open: _menu == _AmountMenu.multiplier,
                            onTap: () => _toggle(_AmountMenu.multiplier),
                          )
                        : widget.leading,
                  ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  onChanged: widget.onChanged,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  cursorColor: textPrimary,
                  style: TextStyle(
                    fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: textSecondary.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
              KeyedSubtree(
                key: _currencyKey,
                child: _AmountSlotButton(
                  label: symbol,
                  color: textSecondary,
                  open: selectable && _menu == _AmountMenu.currency,
                  showChevron: selectable,
                  onTap: selectable
                      ? () => _toggle(_AmountMenu.currency)
                      : null,
                ),
              ),
            ],
          ),
          if (widget.helper != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.helper!,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 11.5,
                color: textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ],
            ],
          ),
        );
      },
    );
  }
}

/// Fade + short drop so the currency / × lists do not pop in fully formed.
class _AmountMenuDrop extends StatefulWidget {
  final Widget child;

  const _AmountMenuDrop({required this.child});

  @override
  State<_AmountMenuDrop> createState() => _AmountMenuDropState();
}

class _AmountMenuDropState extends State<_AmountMenuDrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.08),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Symbol or ×N control. Chevron means a list will open under the row.
class _AmountSlotButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool open;
  final bool showChevron;
  final VoidCallback? onTap;

  const _AmountSlotButton({
    required this.label,
    required this.color,
    this.open = false,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (showChevron)
              Icon(
                open
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 18,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable list that grows downward from the amount row, capped so the
/// sheet does not dump every choice on screen at once.
class _AmountMenuList extends StatelessWidget {
  final List<Widget> children;

  const _AmountMenuList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: ListView(
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
    );
  }
}

class _AmountMenuTile extends StatelessWidget {
  final String title;
  final String? leading;
  final bool selected;
  final bool centered;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _AmountMenuTile({
    required this.title,
    required this.selected,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
    this.leading,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : textPrimary;
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: selected ? accent : textSecondary,
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: centered ? 0 : 4,
          vertical: centered ? 8 : 10,
        ),
        child: centered
            ? Center(child: label)
            : Row(
                children: [
                  if (leading != null) ...[
                    SizedBox(
                      width: 42,
                      child: Text(
                        leading!,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontFamilyFallback: ['Tajawal'],
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                  Expanded(child: label),
                ],
              ),
      ),
    );
  }
}

/// Compact currency control beside an amount; stays static when only one currency is enabled.
class SheetCurrencySelector extends StatefulWidget {
  final String? currencyCode;
  final ValueChanged<String>? onChanged;
  final bool dense;

  const SheetCurrencySelector({
    super.key,
    this.currencyCode,
    this.onChanged,
    this.dense = false,
  });

  @override
  State<SheetCurrencySelector> createState() => _SheetCurrencySelectorState();
}

class _SheetCurrencySelectorState extends State<SheetCurrencySelector> {
  bool _open = false;

  String get _code {
    return Currencies.normalize(
      widget.currencyCode ?? CurrencyStore.instance.activeCode,
    );
  }

  /// Opens the currency list under the symbol. One currency stays a label.
  void _toggle() {
    final options = CurrencyStore.instance.enabledCurrencies;
    if (widget.onChanged == null || options.length < 2) return;
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CurrencyStore.instance,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textPrimary =
            isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
        final textSecondary =
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
        final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
        final options = CurrencyStore.instance.enabledCurrencies;
        final selectable = widget.onChanged != null && options.length > 1;
        final symbol = Currencies.symbolOf(_code);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: selectable ? _toggle : null,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    symbol,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                      fontSize: widget.dense ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  if (selectable)
                    Icon(
                      _open
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      size: widget.dense ? 16 : 18,
                      color: textSecondary,
                    ),
                ],
              ),
            ),
            if (_open)
              _AmountMenuList(
                children: [
                  for (final item in options)
                    _AmountMenuTile(
                      title: item.arabicName,
                      leading: item.symbol,
                      selected: item.code == _code,
                      accent: accent,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onTap: () {
                        widget.onChanged?.call(item.code);
                        setState(() => _open = false);
                      },
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Optional single-line text field styled like other sheet inputs.
class SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const SheetTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: TextAlign.right,
      cursorColor: textPrimary,
      style: TextStyle(
        fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
        fontSize: 15,
        color: enabled ? textPrimary : textSecondary.withValues(alpha: 0.55),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: sheetFieldColor(context),
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
          fontSize: 14,
          color: textSecondary.withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Segmented choice row (same pattern as expense payment-method chips).
class SheetChoiceChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  const SheetChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    if (options.isEmpty) return const SizedBox.shrink();

    final selectedIndex = options.indexOf(selected).clamp(0, options.length - 1);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: sheetFieldColor(context),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / options.length;

            return Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  start: selectedIndex * itemWidth,
                  width: itemWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: accent, width: 1.4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: GestureDetector(
                          onTap: enabled ? () => onSelected(option) : null,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              style: TextStyle(
                                fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                color: option == selected ? accent : textPrimary,
                              ),
                              child: Text(
                                option,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Softly expands or collapses optional sheet content.
class SheetExpand extends StatelessWidget {
  final bool visible;
  final Widget child;

  const SheetExpand({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        layoutBuilder: (currentChild, _) =>
            currentChild ?? const SizedBox(width: double.infinity),
        child: visible
            ? KeyedSubtree(key: const ValueKey('sheet-expand-on'), child: child)
            : const SizedBox(width: double.infinity, key: ValueKey('off')),
      ),
    );
  }
}

/// Cross-fades sheet content when the active option changes.
class SheetSwap extends StatelessWidget {
  final Object switchKey;
  final Widget child;

  const SheetSwap({super.key, required this.switchKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox(width: double.infinity),
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
    );
  }
}

/// Full-width primary save / confirm button at the bottom of a sheet.
class SheetSaveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const SheetSaveButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: enabled ? accent : textSecondary.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit', fontFamilyFallback: ['Tajawal'],
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared fill for sheet inputs: app background blended with a touch of accent.
Color sheetFieldColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final base = isDark ? AppColors.darkBackground : AppColors.lightBackground;
  final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

  return Color.alphaBlend(accent.withValues(alpha: isDark ? 0.10 : 0.07), base);
}

/// Formats amount text with thousand separators while typing (max 9 digits).
class ThousandsInputFormatter extends TextInputFormatter {
  static const int maxDigits = 9;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return const TextEditingValue();

    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.length > maxDigits) return oldValue;

    final formatted = formatMoney(int.parse(trimmed));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Parses a formatted amount string after stripping commas.
double parseAmount(String text) {
  return double.tryParse(text.replaceAll(',', '').trim()) ?? 0;
}
