# Motion widgets

| File | Contents |
| --- | --- |
| `motion.dart` | `Reveal`, `staggered()`, `RollingMoney`, `RollingText`, `AnimatedRatio`, `RevealClip`. |
| `active_listenable_builder.dart` | `ActiveListenableBuilder`: a `ListenableBuilder` that sleeps while its tab is hidden. |
| `liquid_vessel.dart` | `LiquidVessel`: progress as a small vessel that fills, with a slow wave on the surface (flat with reduced motion or on a hidden tab). Used for savings goals. |
| `origin_route.dart` | `originPageRoute(context, builder)` / `OriginPageRoute`: a page that grows out of the tapped widget and folds back on close. Back gestures keep the platform transition, because the platform builder stays mounted underneath. |
| `pressable.dart` | `Pressable`: spring press feedback (the surface sinks under the finger and bounces back) with a selection haptic. Use it for every custom tappable surface. |

`AppMotion` owns durations, curves and the reduced-motion setting.
`AppMotion.enabled(context)` also checks the enclosing `TickerMode`: repeating
effects should sleep when their page is retained outside the visible tab.

- `Reveal` plays once, cancels its stagger timer on disposal, and settles
  immediately if reduced motion is enabled during its entrance.
- `RollingMoney` preserves the visually dominant number when retargeted.
  `RollingText` caches glyph measurements across frames; style and text-scale
  changes invalidate them. Separators use the same scale as digits.
- `AnimatedRatio` animates a bounded ratio and uses its final value directly
  with reduced motion. `RevealClip` only changes the chart's clipping rectangle.
- `ActiveListenableBuilder` is for store-driven content on retained tabs. It
  disconnects its store listener while `TickerMode` is disabled and reads current
  data on return. It preserves child state and does not buffer notifications.
  Do not use it for persistent business tasks that must run off screen.

The shell supplies one `TickerMode` per cached tab. Keep a stable widget/key
across data updates rather than recreating entrance animations.

Regression coverage: `test/motion_lifecycle_test.dart`,
`test/active_listenable_builder_test.dart`, and `test/app_shell_motion_test.dart`.
