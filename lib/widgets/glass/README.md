# lib/widgets/glass

The glass material and the light it bends. Glass is for chrome that floats
over content (header, bottom bar, selectors, sheets, small tooltips); content
cards stay solid so money is always read on a plain surface.

| File | Contents |
| --- | --- |
| `liquid_glass.dart` | `LiquidGlass` (the one glass surface), `GlassPreset` (`crystal`, `liquid`, `frosted`), `LiquidGlassScope` (pause refraction under a fading subtree), `LiquidGlassShader` (loads the lens program once). |
| `aurora_backdrop.dart` | `AuroraBackdrop` (slow soft green lights behind a page, redrawn about fifteen times a second) and `AuroraPage` (a page body on that backdrop). |
| `tilt.dart` | `TiltBuilder` (a spring-smoothed lean from touch and the accelerometer) and `TiltSettings` (the "follow the phone" switch, kept in prefs). |

How the glass is built, back to front: backdrop blur and saturation, edge
refraction, a thin surface tint, rim light and sheen, then the child, which
is never distorted.

- **Refraction** is `shaders/liquid_glass.frag`, run as an
  `ImageFilter.shader` on the backdrop. The shift comes from the shape: the
  rounded-rect distance to the edge, a convex squircle bezel and Snell's law.
  The middle of the glass is untouched. It needs Impeller.
- **Fallback.** Without shader filters (other renderers, web) or with high
  contrast on, the same widget draws blur, tint and light only.
- **Position.** The lens works in screen pixels, so it is only exact while
  the surface is settled. `LiquidGlass` fades refraction out while its route
  animates or a `LiquidGlassScope` says so, and a frame callback repaints a
  lens whose place on screen changed without a repaint.
- **Edges.** `bleed` pushes the optical outline past the widget on sides
  attached to a screen edge: the header has no top bezel, a sheet no bottom
  one.

Do not stack glass on glass, and do not put body text on the `liquid` or
`crystal` presets; use `frosted` for anything with text on it.

Tests: `test/widgets/containers/glass_sheet_keypad_test.dart` covers the
sheet built on this glass. Flutter's test renderer has no shader filters
unless tests run with `--enable-impeller`, so widget tests exercise the
fallback path.
