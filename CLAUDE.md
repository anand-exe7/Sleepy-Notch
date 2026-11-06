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
`ActivityManager` keeps one `LiveActivity` per `ActivityKind` (`privacy`, `charging`, `music`), derived from published state with Combine (no timers except one-shots). The main one sits in the notch's wings; others get a bubble (right side first, then left). A new activity is announced by a peek in `PeekCenter` (`PeekContent.announces`) and then shrinks into its bubble; clicking a bubble opens it as `.activity(kind)` in the notch and it folds away after 5 s. `PeekCenter` = transient notices; `ActivityManager` = persistent state. Batch 2 should extend this, not add a second system. Kinds are a fixed enum (`privacy`, `charging`, `music`, `timer`) and inputs are hard-wired in `start(...)`. At most 2 bubbles: an activity with no free side gets `ActivitySlot.hidden` and is promoted when one frees up. In the "in the notch" status style a timer shows only when it is the main activity.

**Timers** (`Services/System/TimerService.swift`, `Features/Activities/TimerViews.swift`): started from the menu bar (Timer submenu), one one-shot at the end, the ring is one Core Animation animation and the text is `Text(timerInterval:)`, so nothing ticks. Settings switch "Timers".

**Crowded notch: cap, "+N" chip and tray** (`ActivityManager.allocate`, `Features/Activities/ActivityTrayView.swift`): the notch shows the main activity in the wings plus two bubble places. When more is running than two places can show, or the user set an activity to "Tray only" (Settings -> Indicators -> Where Activities Show, `HUDPreferences.trayOnly`), one place becomes a "+N" chip (`ActivityKind.overflow`, never a real activity) and the best N-1 keep bubbles; ranking is attention first (passive states give way: Stay Awake, the agent unless it needs the user), then `ActivityKind.priority`. Clicking the chip, the notch when it shows more than one thing and no song plays, or menu bar -> "Show Running Activities" opens `PeekContent.tray`: one card listing everything with Cancel / Turn Off where there is one. Idea not built: detect menu bar icons next to the notch and fall back to the "In the notch" style.

**System HUDs** (`Services/System/SystemHUDMonitor.swift`, `Features/Peeks/HUDPeekView.swift`, `Core/Models/HUDReading.swift`): volume, brightness and keyboard backlight as a peek (glyph + level bar + percent). Event-driven: CoreAudio property listeners on the default output device ('vmvc' virtual main volume and mute, rebound when the default device changes); brightness through private `DisplayServices` (`DisplayServicesRegisterForBrightnessChangeNotifications`, loaded with `dlsym`); backlight through private `CoreBrightness` `KeyboardBrightnessClient.registerNotificationForKeys:keyboardID:block:` with key `KeyboardBacklightBrightness`. Brightness and backlight only show for a change of 0.04 or more (ambient-light adjustments are smaller; a key step is ~0.06). `PeekCenter.postHUD` updates a showing HUD in place. Runs only while Settings "Volume and brightness" is on and the notch is visible. macOS's own HUDs are NOT hidden: every way to hide them needs polling, killing a system process or an event tap with Accessibility permission. **Stay Awake** (`StayAwakeService`, menu bar item): a `PreventUserIdleDisplaySleep` power assertion, an activity (cup glyph, opened detail with Turn Off); session-only, released by the system if the app dies. **Never open a user folder on the main thread** (`DownloadsMonitor` now opens it on a background queue): the first-launch permission prompt makes `open()` wait and froze the whole app, including every listener on the main queue.

**Eye break** (`Services/System/EyeBreakScheduler.swift`, `EyeBreakPeekViews.swift`): Settings -> Peeks -> "Eye break" (off by default). One pending timer, 20 min, re-armed after each fire; it runs only while the switch is on AND the notch is visible, so lock, display sleep and session switches cancel it and coming back starts a fresh interval. **Local bridge** (`Services/System/LocalBridge.swift`, `scripts/sleepynotch`): Settings -> General -> "Scripting" (off by default). A second `AgentSocketServer` at `~/Library/Application Support/Sleepy Notch/bridge.sock` takes one JSON object: `peek` (text, 80 chars, control chars stripped), `shelf-add` (existing absolute path), `timer` (minutes, 0 < m <= 720), `timer-cancel`. Anything else is dropped; commands closer than 0.4 s apart are dropped. The `sleepynotch://` link form (peek, timer, timer-cancel; deliberately NOT shelf-add) is handled in `AppDelegate.handleURLEvent` and `Info.plist` declares the scheme, but a bare SwiftPM executable can't register a URL scheme: it only works once the app is packaged as an .app (not verified; a temporary signed test bundle was not claimed by LaunchServices).

**Wind-down and good night** (`Services/System/WindDownScheduler.swift`, `Features/Peeks/WindDownPeekViews.swift`): Settings -> Peeks -> "Bedtime reminder" (off by default) plus a time picker. One wall-clock one-shot (`asyncAfter(wallDeadline:)`) for the next occurrence, re-planned after it fires and on wake, unlock, system clock and time zone changes; skipped (not shown late) when the notch isn't visible. The peek is a moon that rises once plus two lines. When a sleep timer ends the peek is "Good night" in Snell Roundhand, written by `WrittenCaption`'s pen-wipe (now takes a font and colour); it does not use `HelloLettering`, whose path is only the word "hello". Not built yet from batch 7: eye-break peek, local bridge.

**Sleep timer** (`TimerService.startSleep`, menu bar -> Sleep Timer 15/30/60): same countdown as the timer (moon icon, "Good night. Music paused"), plus one `osascript` process (`Process`, not the shared runner) that waits, reads the player's volume, steps it to 0 over the last 30 s, pauses and restores the volume; the app never ticks. Targets Music or Spotify (whichever the current song is in; menu items disabled for Demo Mode or nothing playing). Cancelled when the user pauses, by Cancel, and on quit (volume is restored first; SIGTERM/SIGINT/SIGHUP take the same road; only SIGKILL can leave the volume down).

**Agent status** (`Services/System/AgentSocketServer.swift`, `AgentStatusService.swift`, `AgentHookInstaller.swift`, `Features/Activities/AgentViews.swift`): the coding agent's hooks write one JSON event to a Unix socket in `~/Library/Application Support/Sleepy Notch/agent.sock` (dir 0700, socket 0600; a dispatch source wakes only on a connection). `AgentStatusService` maps `UserPromptSubmit` to working, `Notification` to needs-input, `Stop` to done (fades after 25 s), `SessionEnd` removes; a quiet working session is dropped after 15 min (one-shots only). `ActivityKind.agent`: glyph bubble/wings, opened detail lists up to 3 sessions, a notice peek on needs-input/done. Opt-in: Settings -> Agent: switch (off by default) plus Install/Remove Hooks. The installer keeps a byte copy of the settings file and restores it exactly on removal if untouched since, else removes only its own tagged entries. Hook command exits at once when the socket is absent. Known limit: after the user approves a request the state stays needs-input until the agent stops (there is no hook for it that doesn't fire on every tool call).

**Mic** (`PrivacyIndicatorMonitor`, `MicLevelMonitor`, `MicWaveView`): the mic bubble shows live voice waves (Settings: Voice waves). The live level only opens the mic on macOS 14+. macOS dictation and Siri are NOT detectable: CoreAudio does not list them as using the mic, so they never show the bubble. Real apps (calls, Voice Memos) do. Feature Lab -> "Simulate mic in use" listens to the real mic for testing.

## Master plan status (PDF is not edited; this is the live copy)
- Step 0 done: idle hover card, glass hello (now plain thick translucent white).
- Batch 1 done: lock screen card (built, seen on the real lock screen). Open: confirm position clear of the avatar/prompt and the live scrubber there.
- Not in the plan, done: likes and playlists (Apple Music only). Spotify dropped.
- Friend's bubbles/activities merged; overlaps batch 2 (see above).
- Batch 2 done (mic fixes, timers, mic bubble waves, downloads ring; screen recording timer skipped: no event-driven signal). Batch 2.5 (agent status) done on `feat/agent-status`. Next: 3, 4, 5, 6, 7, 8.
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
