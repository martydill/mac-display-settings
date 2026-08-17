# Display Settings (macOS)

A SwiftUI app that replicates the Windows "Display Settings" panel
(resolution, orientation, arrangement, main-display, mirroring), plus a
Finder Sync extension that adds a **"Display Settings"** item to the
right-click menu on your Desktop.

The repository includes a ready-made `DisplaySettingsApp.xcodeproj`
(verified building and running with Xcode 26.6 on macOS 26) — just open
it and press ⌘R.

## What's included

```
DisplaySettingsApp/
  DisplaySettingsApp.xcodeproj/
  MainApp/
    DisplaySettingsAppApp.swift    - app entry point + URL-scheme handling + onboarding trigger
    ContentView.swift              - the Windows-style Display Settings UI
    DisplayManager.swift           - all the CoreGraphics display logic
    OnboardingView.swift           - first-run "enable the Finder extension" sheet
    FinderExtensionHelper.swift    - deep-links into System Settings' Finder Extensions pane
    Info.plist                     - app Info.plist (registers the displaysettings:// URL scheme)
    Assets.xcassets/               - app icon (generated placeholder — swap for your own art)
  FinderSyncExtension/
    FinderSync.swift               - adds the Desktop right-click menu item
    Info.plist                     - extension Info.plist (NSExtension principal class)
    DisplaySettingsFinderExtension.entitlements  - App Sandbox (required for Finder Sync)
  README.md                        - this file
```

## 1. Open & run

Open `DisplaySettingsApp.xcodeproj`. The project is already set up with
two targets — **DisplaySettingsApp** (the app) and
**DisplaySettingsFinderExtension** (the embedded Finder Sync extension) —
so there's nothing to configure by hand:

- Bundle IDs are `com.marty.displaysettingsapp` and
  `com.marty.displaysettingsapp.finderextension`; change them on the
  targets' Signing & Capabilities tabs if you want your own prefix.
- The app target is **not sandboxed**, because changing display
  configuration is not permitted for sandboxed apps. This means you
  distribute the app directly (e.g. notarized DMG), not through the Mac
  App Store.
- The extension target keeps **App Sandbox** on, as Finder Sync
  extensions require. No special entitlements are needed since it only
  opens a URL, which is allowed from a sandboxed extension.
- The `displaysettings://` URL scheme is registered in
  `MainApp/Info.plist`.
- `FinderSync.framework` is linked to **both** targets — the main app
  needs it too, for
  `FIFinderSyncController.showExtensionManagementInterface()` (see
  `FinderExtensionHelper.swift`), which deep-links users straight to the
  System Settings toggle from the first-run onboarding sheet and from
  the permanent "Enable Desktop Menu…" link in the sidebar.
- The extension is embedded into the app's `PlugIns/` automatically on
  every build.

## 2. Build & first run

1. Build and run the **DisplaySettingsApp** scheme (⌘R) once, then quit
   it — this installs both the app and the embedded extension into
   `/Applications` (or wherever you run it from) so macOS can find it.
2. Open **System Settings → General → Login Items & Extensions →
   Extensions → Finder**, and enable **DisplaySettingsFinderExtension**.
   (On older macOS: **System Settings → Extensions → Finder Extensions**.)
3. Right-click empty space on your Desktop → you should see **Display
   Settings** in the menu. Clicking it launches/foregrounds the app.

If the item doesn't appear immediately, log out and back in, or run:
```
killall Finder
```

## Changes from a code review pass

A few real bugs were caught and fixed after the first draft:

- `DisplayMode`'s `==` compared two `CGDisplayMode` values directly, but
  that type has no `==` operator — this would not have compiled. Now
  compares `ioDisplayModeID` + pixel dimensions instead.
- The Desktop-URL lookup in the Finder extension force-unwrapped
  (`.first!`); a nil there would have crashed the Finder extension host
  process, not just this app. Now handled safely.
- `NSScreenNumber` was cast straight to `CGDirectDisplayID`; it's stored
  as `NSNumber`, so that cast was unreliable and made display names fall
  back to generic ones more often than necessary. Fixed to go through
  `NSNumber.uint32Value`.
- The `CGDisplayReconfigurationCallback` was registered but never
  removed, which could crash into a dangling pointer if `DisplayManager`
  were ever deallocated. Added matching cleanup in `deinit`.
- **Added a missing safety feature**: resolution changes show a "Keep
  these display settings?" bar with a 15-second countdown that
  auto-reverts, matching what Windows and macOS's own System Settings do
  so a bad change can't leave you staring at an unreadable screen.

## Changes from a polish pass

- **Refresh-rate display bug**: modes with `refreshRate == 0` (most
  fixed-refresh panels) were being shown as a fabricated "60Hz". Now
  shown with no rate at all when the display doesn't actually report one.
- **Empty state**: the Display page no longer renders an empty canvas if
  `CGGetActiveDisplayList` briefly returns zero displays (e.g. right
  after a hot-plug) — shows a message and a Detect button instead.
- **Accessibility**: VoiceOver labels/hints added to the drag-to-arrange
  tiles (custom-drawn, so they had no accessible description at all
  before), the resolution/multi-display pickers, and the
  revert-safety bar.
- **First-run onboarding**: a one-time sheet on first launch explains the
  Finder extension and deep-links straight to System Settings' Finder
  Extensions pane via `FIFinderSyncController.showExtensionManagementInterface()`
  — the same mechanism is also always available from a permanent
  "Enable Desktop Menu…" link in the sidebar, since first-run dialogs get
  dismissed and forgotten.
- **Quit behavior**: added `applicationShouldTerminateAfterLastWindowClosed`
  so this single-purpose utility quits when its one window closes,
  instead of lingering invisibly in the Dock.
- **Real app icon**: `Assets.xcassets/AppIcon.appiconset` now ships a
  generated placeholder icon at every required macOS size (Xcode
  rejects archiving without one). Swap the PNGs for real artwork before
  shipping.

## Changes from a second bug-hunt pass

- **Fixed — quitting mid-countdown silently defeated the safety net.**
  The revert-safety countdown (added in the polish pass) runs on a
  `Timer` inside the app process. If the user quit — or just closed the
  window, which now quits the app too — while a resolution
  change was still unconfirmed, the process died with the timer and the
  change was never reverted, exactly the scenario the feature exists to
  prevent. `AppDelegate` now holds a weak reference to `DisplayManager`
  and reverts any pending change in `applicationShouldTerminate` before
  allowing the app to quit.
- **Fixed — dragging the *main* display could produce an invalid
  arrangement.** CoreGraphics requires exactly one display to sit at
  `(0,0)` — that's what makes it "main." `moveDisplay` was moving only
  the dragged display, so dragging the main display left nothing at the
  origin. It now detects that case and shifts every display by the same
  delta instead (same technique `makeMain` already used), preserving the
  origin invariant.
- **Fixed — cosmetic**: a `Spacer()` inside the sidebar `List` was meant
  to visually separate the "Enable Desktop Menu…" link, but `List` rows
  aren't a `VStack` — it just rendered as a fixed blank row rather than
  pushing anything. Replaced with a `Section`.

## Changes from the first real build

This code was originally written without access to macOS/Xcode, so it
had never been compiled until the Xcode project was added. First build
surfaced four compile errors, all fixed:

- The Finder extension used `NSWorkspace.shared.open(url) { … }`, which
  doesn't exist with a bare trailing closure — resolved to the
  dictionary-based legacy overload that Swift can't see. Now uses the
  modern `open(_:configuration:completionHandler:)` with an
  `NSWorkspace.OpenConfiguration`.
- `CGDisplayMode.isUsableForDesktopGUI` is imported into Swift as a
  method, not a property — now called with `()`.
- `CGDisplayCopyColorSpace` imports as non-optional and
  `CGColorSpaceCopyName` is replaced by the `name` property (returning
  `CFString?`); `colorSpaceName` was rewritten accordingly.
- `revertPendingChange()` had a `guard` whose body only recorded an
  error and fell through — a compile error, and the intent was to
  `reload()` either way, so it's now a plain `if`.

## Current implementation notes

The latest bug-fix pass addresses the display-state issues identified during review:

- Resolution changes use a full pre-change display snapshot for rollback.
- While a resolution change is awaiting confirmation, all other display-changing controls are disabled.
- Quitting while a resolution change is pending still restores the snapshot before termination.
- Display configuration return values are checked and failed transactions are cancelled/reported.
- The CoreGraphics reconfiguration callback ignores the pre-configuration callback phase.
- Active-display enumeration errors no longer replace a good display model with an empty one.
- Mirrored secondary displays cannot be assigned an independent resolution.
- Display modes have stable identities and retain refresh-rate distinctions.
- Arrangement dragging snaps edges and prevents display rectangles from overlapping.
- The main display cannot be dragged away from `(0,0)`; another display must be made main first.
- Identify overlays use local view coordinates and Auto Layout, so they work on secondary displays.
- The arrangement canvas scales dynamically to fit the current desktop geometry.
- Display rotation controls have been intentionally removed so the application uses only public macOS APIs.

## Notes & limitations

- **Resolution / arrangement / mirroring / make-main-display** use public
  `CoreGraphics` display-configuration APIs.
- **Display rotation is not implemented.** macOS does not provide a public
  API for setting display rotation, so this application deliberately omits
  that feature rather than relying on private or undocumented APIs.
- **Brightness / Night Shift** aren't implemented because reliable public
  APIs for external-display brightness and Night Shift control are not
  available for this application.
- **URL scheme hijacking**: the Finder extension launches the app via
  `displaysettings://open`. Custom URL schemes are a shared, unverified
  namespace. Since the URL carries no data and only brings this app forward,
  the practical risk is low.
- Code signing: Finder Sync extensions must be properly signed to be enabled
  reliably. For distribution to others, use a Developer ID certificate and
  notarization.

## Windows Display Settings parity

The current public-API-only build includes:

- Display scaling/effective-resolution choices, including HiDPI modes.
- Independent refresh-rate selection where macOS exposes selectable modes.
- A display-mode control for extending or duplicating displays.
- A Windows-style Identify and Detect workflow.
- Advanced display information including physical/effective resolution, refresh rate, physical size, color space, and public Core Graphics hardware identifiers.
- Recommended-mode labeling using the closest public macOS representation of the current logical display size. macOS does not expose a public universal "recommended resolution" flag.

The app intentionally does not provide Windows' "show only on 1/2" modes because public macOS display-configuration APIs do not expose a supported way to disable an individual display.
