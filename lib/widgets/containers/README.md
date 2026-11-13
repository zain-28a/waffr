# Shared surfaces, sheets and pinned period controls

| File | Contents |
| --- | --- |
| `glass.dart` | `GlassContainer` (solid tinted content card, `GlassColorType`), `liquidGlassFill()` and `LiquidGlassPainter` (rim). No live blur: content cards are not glass. |
| `floating_glass.dart` | `FloatingGlass` (a `LiquidGlass` pill) and `FloatingGlassHighlight` (tinted selection bubble). |
| `amount_keypad.dart` | `AmountKeypad` (digits, delete, done and the quick amounts), `QuickAmounts` (the editable list, 10/25/50/100/200/500 by default, kept in prefs), `showQuickAmountsEditor`, and `AmountKeypadScope` / `AmountKeypadController` that let a sheet dock the keypad. |
| `pinned_period_scroll_view.dart` | `PinnedPeriodScrollView` and `FloatingPeriodSelector` for Reports and Savings. |
| `glass_sheet.dart` | `showGlassSheet` (frosted `LiquidGlass` sheet that follows Android's predictive back gesture and docks the amount keypad at the bottom of the screen), `GlassSheetBody`, `GlassSheetFixedBody`, `GlassSheetHeader`, `kSheetBarrierColor`. Re-exports the four `sheet_*.dart` files. |
| `sheet_fields.dart` | `SheetFieldLabel`, `SheetInfoButton` (the (i) help), `SheetOptionTile`, `SheetTextField`, `SheetChoiceChips`, `sheetFieldColor()`. |
| `sheet_amount_field.dart` | `SheetAmountField` (large amount typed on Waffr's own keypad, currency list, ×1-×10 multiplier), `SheetCurrencySelector`, `ThousandsInputFormatter`. |
| `sheet_transitions.dart` | `SheetExpand` (show/hide a section) and `SheetSwap` (cross-fade on option change). |
| `sheet_buttons.dart` | `SheetCircleButton` (header close/next), `SheetSaveButton` (wraps `AppPrimaryButton`), `SheetDestructiveButton`. |
| `app_list_tile.dart` | `AppListTile` (settings-style row card with icon, status chip, chevron) and `AppSectionTitle`. |
| `app_empty_state.dart` | `AppEmptyState`: the one "nothing here yet" block. |

`glass_sheet.dart` was split; import only it and you get every sheet piece.
The sheet barrier is a light flat dim; only glass surfaces blur what is
behind them, and content cards stay solid. Floating chrome uses `LiquidGlass`
(`widgets/glass/`); change `FloatingGlass` and `FloatingGlassHighlight` to keep
the navigation bar and the period selector aligned.

The amount field never opens the system keyboard. While it has focus the
keypad is docked under the sheet, along the bottom edge; outside a sheet it
opens under the field. Another text field taking focus closes it.

`PinnedPeriodScrollView` gives Reports and Savings one vertical scroll view.
Its fixed-extent pinned sliver keeps `FloatingPeriodSelector` below the shell
header while content passes beneath it; layout constants such as
`kFloatingNavClearance` come from `screens/shell/app_shell_scope.dart`. Period
choices animate in the reading direction, expose their selected state to
accessibility, and scroll horizontally when labels do not fit, using an
owned controller so the page's vertical offset is kept. Reduced motion uses
immediate selection changes.

`test/pinned_period_selector_test.dart` exercises both real screens after
scrolling, period-pager reset, stable vertical position, and the scaled RTL
dark-mode selector.
