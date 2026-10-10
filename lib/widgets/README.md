# lib/widgets

Controls used by more than one feature. Feature-only widgets stay next to
their screen.

| Path | Use it for |
| --- | --- |
| `containers/glass.dart` | `GlassContainer`. Translucent card. No backdrop blur. |
| `button/glass_button.dart` | The same surface with a press scale. |
| `button/app_primary_button.dart` | The app's single primary action button (forms, screens, and sheets via `SheetSaveButton`). |
| `containers/glass_sheet.dart` | Modal sheet shell, labels, amount field, chips, option rows, the (i) `SheetInfoButton`, save button. |
| `dialogs/edit_amount_dialog.dart` | Edit a single amount. |
| `dialogs/waffr_date_picker.dart` | Date and date-range picker with a typed field above the calendar. |
| `dialogs/edit_delete_menu.dart` | The long-press edit / delete menu for tiles. |
| `sheets/monthly_income_required_sheet.dart` | Prompt when a flow needs a monthly income first. |
| `brand/waffr_logo.dart` | Logo and the startup splash. |
| `brand/streak_celebration.dart` | The overlay shown when the streak grows on app open. |
| `brand/waffr_page_header.dart` | The top bar. Pushed screens use `WaffrBackHeader` (back arrow + centered title). |
| `brand/profile_avatar.dart` | Circular avatar, with an optional camera badge. |
| `motion/animated_number_text.dart` | Numbers that count to a new value (balances, percentages). |
| `motion/fade_slide_in.dart` | One-time fade-and-rise entrance for list rows, with a stagger helper. |

New sheets should start from `glass_sheet.dart` instead of copying the
padding and the header row. Short explanations open through
`SheetInfoButton` / `showAppInfoDialog`, and confirmations through
`showAppConfirmDialog`, so every (i) and every question looks the same.
