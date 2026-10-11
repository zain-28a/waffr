# Shared surfaces and pinned period controls

`GlassContainer` is the lightweight tinted surface for content cards and
`glass_sheet.dart` contains modal sheet controls. Content cards avoid live blur.

`FloatingGlass` supplies the clipped 18px backdrop blur, translucent fill,
rounded rim and shadow shared by the navigation bar and period selector.
`FloatingGlassHighlight` supplies their tinted selection bubble. Change these
shared widgets when updating the floating chrome so both controls stay aligned.

`PinnedPeriodScrollView` gives Reports and Savings one vertical scroll view.
Its fixed-extent pinned sliver keeps `FloatingPeriodSelector` below the shell
header while content passes beneath it. The header reserves space at the top;
bottom content retains the floating navigation clearance.

Period choices animate in the reading direction and expose their selected
state to accessibility. If labels do not fit (small screens or enlarged text),
the row scrolls horizontally and keeps the chosen period visible. Its owned
scroll controller adjusts only that row, preserving the page's vertical offset.
Reduced motion uses immediate selection changes.

`test/pinned_period_selector_test.dart` exercises both real screens after
scrolling, period-pager reset, stable vertical position, and the scaled RTL
dark-mode selector.
