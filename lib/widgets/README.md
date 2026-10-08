# lib/widgets

Controls used by more than one feature. Feature-only widgets stay next to
their screen.

| Path | Use it for |
| --- | --- |
| `containers/glass.dart` | `GlassContainer`. Translucent card. No backdrop blur. |
| `button/glass_button.dart` | The same surface with a press scale. |
| `button/ani_pri_button.dart` | Primary button with a press animation. |
| `containers/glass_sheet.dart` | Modal sheet shell, labels, amount field, chips, save button. |
| `dialogs/edit_amount_dialog.dart` | Edit a single amount. |
| `dialogs/waffer_date_picker.dart` | Date and date-range picker with a typed field above the calendar. |
| `dialogs/edit_delete_menu.dart` | The long-press edit / delete menu for tiles. |
| `sheets/monthly_income_required_sheet.dart` | Prompt when a flow needs a monthly income first. |
| `brand/waffer_logo.dart` | Logo and the startup splash. |
| `brand/streak_celebration.dart` | The overlay shown when the streak grows on app open. |
| `brand/waffer_page_header.dart` | The top bar used by the shell and some pushed screens. |
| `brand/profile_avatar.dart` | Circular avatar, with an optional camera badge. |

New sheets should start from `glass_sheet.dart` instead of copying the
padding and the header row.
