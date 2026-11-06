# Sleepy-Notch — project map

macOS (13+, built against SDK 26 for Liquid Glass) menu-bar-less "notch HUD" in Swift/SwiftUI/AppKit. A frameless panel sits at the MacBook camera notch; hover expands it into a music player. Also shows "peeks" (transient cards) for charging, headphones, keyboard locks, meetings, clipboard copy, track changes, plus a file Shelf and a Settings window. ~97 files, ~10.8k lines, SwiftPM executable (no tests, no Xcode project).

Build/run: `swift build` / `swift run` / `swift build -c release`. Energy check: `scripts/measure-energy.sh [secs]`. `Support/Info.plist` is embedded via linker flags in `Package.swift` (calendar usage strings). Don't touch the `-platform_version` flags.

README.md is partly stale (describes an old/proposed layout, `MediaManager`, `NotchWindowManager`). Trust this file and the code.

## Rules (from the README, still valid)
- Layering: `Core/` + `Services/` never import `Features/` or `DesignSystem/`. `DesignSystem/` never imports `Features/`. `App/` is the only place concrete types are wired (`AppEnvironment`).
- Battery: zero polling; event-driven (DistributedNotificationCenter, IOKit, CoreAudio, etc.). Collapsed/paused notch must stop all timers/render loops. Target ~0% idle CPU.
- Spring: response 0.36, damping 0.78; hover-exit is debounced.
- One primary type per file; no `public`.

## Startup flow (`Sources/SleepyNotch/`)
`App/SleepyNotchApp.swift` (`@main AppMain`, accessory app) → `AppDelegate` → `AppEnvironment` (builds all long-lived objects) → `AppWiring.start()` (routes monitor events into `PeekCenter`/`NotchStatus`; also holds Feature Lab simulations) → `NotchWindowController` (panel + SwiftUI `NotchView`). `WelcomeCoordinator` runs first-launch intro.

## App/
- `SleepyNotchApp.swift` entry · `AppDelegate.swift` lifecycle · `AppEnvironment.swift` DI container · `AppWiring.swift` event→HUD wiring (+ lab sims) · `StatusItemController.swift` NSStatusItem menu · `MainMenu.swift` · `AppIcon.swift`

## Core/ (pure models/support)
- Models: `TrackInfo`, `TrackChange` (+`TrackSnapshot`), `MusicSource` (Apple Music/Spotify/demo), `PowerEvent`, `HeadphoneEvent` (+`HeadphoneModel`, `HeadphoneBattery`), `NotchIndicators` (`NotchStatus` observable, `NotchIndicators`, `KeyboardEvent`, `MeetingReminder`, `ClipboardPreview`)
- Support: `NotchMetrics` (notch size constants/geometry), `TimeFormatting`

## Services/
- Media: `PlaybackCoordinator` (448 lines; central observable playback state, source switching, optimistic toggle settle), `PlaybackSource` protocol, `AppleMusicSource`, `SpotifySource`, `DemoSource` (+`DemoArtwork`), `ScriptablePlayer` (shared AppleScript player logic)
- IPC: `AppleScriptRunner`, `RunningAppProbe`
- Artwork: `ArtworkCache`, `ArtworkPalette` (dominant colors)
- Files: `ThumbnailLoader` (shelf thumbnails)
- System: `PowerSourceMonitor` (IOKit battery/AC events), `PowerStateMonitor` (low power/thermal), `AudioDeviceMonitor` (headphone connect), `BluetoothBatteryReader`, `PrivacyIndicatorMonitor` (mic/camera dots), `KeyboardMonitor` (caps lock etc.), `CalendarMonitor` (EventKit meeting reminders), `ClipboardMonitor`, `ProductImages` (headphone images), `SystemSettings`, `BootSession`
- Window: `NotchWindowController` (panel lifecycle, hover/hysteresis, screen changes), `NotchPanel` (+`NotchHitView` notch-shaped hit testing), `NotchGeometryProvider` (notch detection per display), `MissionControl`

## DesignSystem/ (shared visuals)
`NotchShape`/`NotchClip` (bezier notch), `NotchSurface` (glass/finish backdrop), `Theme`, `CoverArtView`, `ArtworkTransition(+Container)`, `EqualizerBars`, `WaveformVisualizer`, `MarqueeText`, `PressScaleButtonStyle`, `TuckTransition` (melt/tuck + `NotchContentReveal`), `IntroClock` (shared intro timing)

## Features/
- Notch: `NotchView` (690 lines, root morphing container), `CompactNotchView`, `NotchCardContent` + `CardTabBar` (tabs: player/shelf), `NotchLayout`, `NotchInteractionState`, `StatusWingsView` (privacy dots, charging level)
- Player: `ExpandedPlayerView`, `PlayerScrubber`, `TransportControls`, `PlaybackClockSchedule`
- Peeks: `PeekCenter` (queue/priority of `PeekContent`), `PeekView`, and per-kind views: `TrackPeekView`, `ChargingPeekView` + `ChargingGauges`, `HeadphonePeekView` (674 lines) + `HeadphoneModel+Symbol` + `RegularAirPodsCase`, `KeyboardPeekView`, `MeetingPeekView`, `CopyPeekView`, `ProductVideo`
- Shelf: `ShelfStore`, `ShelfView`, `ShelfItemView`, `ShelfDropZone`, `ShelfActions`
- Settings: `SettingsWindowController`, `SettingsView`, `SettingsPane`, `SettingsComponents`, `HUDPreferences` (UserDefaults-backed toggles)
- Welcome: `WelcomeCoordinator`, `WelcomePeekView`, `HelloLettering`, `WrittenCaption`
- Lab: `FeatureLabMenu` (debug menu to simulate peeks)

## Where to look for common tasks
- New peek type: add case to `PeekContent` (PeekCenter) → view in `Features/Peeks` → render in `PeekView` → event source in `Services/System` → wire in `AppWiring` → toggle in `HUDPreferences`/`SettingsView`.
- New music source: implement `PlaybackSource`, register in `AppEnvironment` / `PlaybackCoordinator`.
- Notch size/position bugs: `NotchMetrics`, `NotchGeometryProvider`, `NotchWindowController`, `NotchPanel`.
- Animation/morph: `NotchView`, `NotchLayout`, `NotchShape`, `TuckTransition`, `NotchSurface`.

## Added since the first map
- `Services/Window/SkyLightSpace.swift` (private SkyLight calls via `dlsym`; a window space above the lock screen) · `Features/LockScreen/` (`LockScreenController` listens for lock/unlock; `LockScreenCardView` = cover, title, scrubber, transport; tap the cover for large art; verified on the real lock screen) · Settings → "Lock screen card" (on by default).
- `Features/Notch/IdleCardView.swift`: hover card with nothing playing (decided when the card opens; `NotchInteractionState.idleCard`).
- `Services/Library/` + `Features/Player/LibraryButtons.swift`: heart and playlist menu on the card. **Apple Music only** (AppleScript `favorited`, `duplicate … to playlist`); Demo Mode has an in-memory fake; no buttons on Spotify tracks (Spotify web API was tried and dropped).
- Friend's work (merged from `like-dynamic`): `Features/Activities/ActivityManager.swift` + `ActivityViews.swift` (live activities, see below), `DesignSystem/NotchBubble.swift` (side bubbles), `DesignSystem/MicWaveView.swift` + `Services/System/MicLevelMonitor.swift` (voice waves), `StatusWingsView` rewrite, `HUDPreferences.statusStyle` / `voiceWaves`.
- `PlaybackCoordinator`: waits 1.5 s before clearing the song on "Stopped" (skips report it), and one one-shot re-check when a song should end (so the card can't sit on a finished ad; unconfirmed with a real ad).
- Welcome hello is now a thick, see-through, glossy white pen line (two shape layers); no colour.

## Live activities (how they work now)
`ActivityManager` keeps one `LiveActivity` per `ActivityKind` (`privacy`, `charging`, `music`), derived from published state with Combine (no timers except one-shots). The main one sits in the notch's wings; others get a bubble (right side first, then left). A new activity is announced by a peek in `PeekCenter` (`PeekContent.announces`) and then shrinks into its bubble; clicking a bubble opens it as `.activity(kind)` in the notch and it folds away after 5 s. `PeekCenter` = transient notices; `ActivityManager` = persistent state. Batch 2 should extend this, not add a second system. Known limits: only 2 bubbles (a third non-main activity would reuse the left slot), kinds are a fixed enum, inputs are hard-wired in `start(...)`.

## Master plan status (PDF is not edited; this is the live copy)
- Step 0 done: idle hover card, glass hello (now plain thick translucent white).
- Batch 1 done: lock screen card (built, seen on the real lock screen). Open: confirm position clear of the avatar/prompt and the live scrubber there.
- Not in the plan, done: likes and playlists (Apple Music only). Spotify dropped.
- Friend's bubbles/activities merged; overlaps batch 2 (see above).
- Next: batch 2 (downloads ring, timers; screen recording timer only if an event-driven signal exists), then the agent-status batch 2.5, 3, 4, 5, 6, 7, 8.
- Open: open-card CPU (~1.5-2% with a still card) unexplained; Spotify ad fix unconfirmed; DMG packaging (app bundle, Automation usage text in Info.plist, signing) not started.
- Workflow: one branch per feature (`feat/<name>` from the current feature branch), local commits only, never push, stop after each feature for the user's check.

## Git
Feature work happens on the long-running feature branch; `main` is the release line. Recent work: lock screen card, idle card, likes/playlists, friend's activities merged.

## Build rules (master plan)
- Event-driven only: system notifications and one-shot timers. No polling, no repeating timers. Nothing animates once settled; everything stops when nobody can see it.
- Every feature is a Settings switch and costs nothing when off.
- Deployment target macOS 13; newer APIs behind `#available`. Private APIs load through `dlsym`; a missing symbol turns the feature off quietly.
- Command Line Tools only (no Xcode): no `@State`; view state lives in small `ObservableObject` classes.
- Design: Apple-native, San Francisco, colour only for status, no coloured glows or looping motion. Things rise on `.timingCurve(0.16, 1, 0.3, 1)` and play once.
- Process: never push or open a PR; commit only when asked (or at a passed checkpoint); leave README and LICENSE alone; stop after each feature for the user's check.
- Licence: treat as MIT. Never copy GPL code (Atoll, SlimHUD); read only.
