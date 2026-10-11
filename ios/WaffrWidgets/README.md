# iOS home screen widgets

The widget code is ready (`WaffrWidgets.swift`), but iOS needs a widget
extension target that only Xcode can create. One-time setup on a Mac:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension.** Name it `WaffrWidgets`,
   untick "Include Configuration App Intent" and "Include Live Activity",
   then **Finish** (and **Activate** the scheme if asked).
3. Xcode creates a `WaffrWidgets` folder with sample files. Delete the
   generated `.swift` files and add this folder's `WaffrWidgets.swift`,
   `Info.plist`, `WaffrWidgets.entitlements`, `Assets.xcassets` (the logo
   on the streak widget) and the `Fonts` folder (Tajawal and Outfit, the
   app's fonts) to the target instead.
4. Select the **Runner** target → **Signing & Capabilities → + Capability
   → App Groups**, and add `group.com.waffr.app`. Do the same for the
   **WaffrWidgets** target (or point its *Code Signing Entitlements*
   build setting at `WaffrWidgets/WaffrWidgets.entitlements`).
5. Set the extension's deployment target to the same iOS version as
   Runner (16 or later), then build and run.

The app already sets the App Group and reloads the widgets
(`lib/data/services/home_widget_sync.dart`), and the `waffr://` URL
scheme in `Runner/Info.plist` routes widget taps.
