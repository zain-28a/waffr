# lib/widgets/glass

The glass material and the light it bends. Glass is for chrome that floats
over content (header, bottom bar, selectors, sheets, small tooltips); content
cards stay solid so money is always read on a plain surface.

| File | Contents |
| --- | --- |
| `liquid_glass.dart` | `LiquidGlass` (the one glass surface), `GlassPreset` (`crystal`, `liquid`, `frosted`), `LiquidGlassScope` (pause refraction under a fading subtree), `LiquidGlassShader` (loads the lens program once). |
| `aurora_backdrop.dart` | `AuroraBackdrop` (slow soft green lights behind a page, redrawn about fifteen times a second) and `AuroraPage` (a page body on that backdrop). |
| `tilt.dart` | `TiltBuilder` (a spring-smoothed lean from touch and the accelerometer) and `TiltSettings` (the "follow the phone" switch, kept in prefs). Apply the lean as the outermost transform of the surface, outside its clip and shadow, so the whole object turns and no edge is left behind. |

How the glass is built, back to front: the lens, which displaces the
backdrop along the outline; blur and saturation of the bent backdrop; a thin
surface tint; rim light and sheen; then the child, which is never distorted.

- **The lens** is `shaders/liquid_glass.frag`, run as an
  `ImageFilter.shader` on the backdrop (Impeller only). The displacement
  follows the shape: the rounded-rect signed distance gives how far a pixel
  is from the outline and which way the outline faces. In a band along the
  outline (`GlassPreset.thickness` deep) each pixel shows the backdrop from
  further in: `GlassPreset.refraction` pixels at the outline, easing to
  nothing where the band ends. The flat middle is untouched. One texture
  read per pixel; no color fringe.
- **Smooth corners.** Inside the band the lens follows a shape whose corners
  are at least as round as the band is deep, so the direction of the shift
  never jumps along a corner's diagonal.
- **Order.** The lens runs before the blur. The other way round it would
  stretch the blur's low-resolution image, which shows as steps at the rim.
- **Tuning.** Keep `refraction` at about two thirds of `thickness` or less;
  more folds the backdrop over itself at the rim. How visible the bend is
  depends on the rest of the preset: clear under light blur and a thin tint
  (bars and pills), faint under heavy frost and a near-opaque tint (sheets).
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
