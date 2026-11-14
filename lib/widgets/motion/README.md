# Motion widgets

| File | Contents |
| --- | --- |
| `motion.dart` | `Reveal`, `staggered()`, `RollingMoney`, `RollingText`, `AnimatedRatio`, `RevealClip`. |
| `active_listenable_builder.dart` | `ActiveListenableBuilder`: a `ListenableBuilder` that sleeps while its tab is hidden. |
| `liquid_vessel.dart` | `LiquidVessel`: progress as a small vessel that fills, with a slow wave on the surface (flat with reduced motion or on a hidden tab). Used for savings goals. |
| `origin_route.dart` | `originPageRoute(context, builder, radius:)` / `OriginPageRoute`: a page that grows out of the tapped widget, the way an app opens from its icon, and shrinks back into it on close. The page below stays in place under a light dusk. A caller that already fills the screen gets the plain slide. |
| `slide_route.dart` | `SlidePageTransitionsBuilder` (the theme's page transition on Android: the new page slides in from the right, the old one eases aside and dims, and leaving plays it backwards) and `SlideOverTransition`. The back gesture is a sideways slide as well: the page travels with the finger (right for a swipe from the left edge, left for one from the right edge, via `SlidePageTransitionsBuilder.side`) and leaves that way. |
| `route_back_gesture.dart` | `RouteBackGesture`: scrubs a route's own transition with Android's predictive back gesture, then pops the route from where the finger left it or returns it. It pops through the navigator itself, because `TransitionRoute.handleCommitBackGesture` snaps the route fully open before playing the exit. Used by the slide and origin routes and by glass sheets. `invertCurve` maps a wanted position back to an animation value. |
| `tap_haptics.dart` | `TapHaptics`: wraps the app and plays `AppHaptics.tick()` for every tap that lands on something tappable; drags, long presses and taps on empty space stay silent. |
| `pressable.dart` | `Pressable`: spring press feedback (the surface sinks under the finger and bounces back). Use it for every custom tappable surface. |

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

Which route to use: a page reached from the header or from a list of
settings is a plain `MaterialPageRoute` (it slides); a page opened by a
button or card inside a screen (a history, the smart analysis) uses
`originPageRoute` with that widget's context.

Regression coverage: `test/motion_lifecycle_test.dart`,
`test/active_listenable_builder_test.dart`, and `test/app_shell_motion_test.dart`.
