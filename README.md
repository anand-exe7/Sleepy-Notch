# 🌙 Sleepy-Notch (macOS Notch Music Player)

> **A liquid-smooth, battery-efficient macOS music controller that seamlessly pops out from the MacBook camera notch on hover.**

Sleepy-Notch integrates directly into macOS ProMotion displays, providing instant media controls, track artwork, and animated waveforms for **Apple Music** and **Spotify** with near-zero CPU and battery footprint.

---

## 🎯 Project Vision & Core Principles

1. **Native Notch Integration (Not an intrusive Dynamic Island clone):**
   - In collapsed state, it sits flush against the MacBook camera housing, subtly displaying mini artwork and a minimalist audio waveform without obstructing menu bar items.
   - On cursor hover, it smoothly springs downward into an expanded, high-fidelity music controller card.
2. **Zero-Battery Architecture (< 0.1% Idle CPU):**
   - **Zero Polling:** Uses event-driven macOS `DistributedNotificationCenter` notifications (`com.apple.Music.playerInfo` and `com.spotify.client.PlaybackStateChanged`).
   - **Hibernation State:** When collapsed or paused, all timers, render loops, and scrubber updates are completely stopped. The collapsed notch is fully still, and everything also stops while the display sleeps, the screen is locked, or the HUD is hidden.
   - **Hardware Acceleration:** Native SwiftUI vector geometry and Metal rendering without web views or Electron overhead.
3. **Dual App Support:**
   - Seamlessly works with both **Apple Music** and **Spotify**.
   - Built-in **Demo Mode** for testing UI/animations. It only starts by hand (menu bar or `d`) and starts paused; with no music app open, the HUD shows a still "No Track Playing" card.
4. **Fluid 120Hz Spring Physics:**
   - Tuned Apple interactive spring physics (`response: 0.36`, `dampingFraction: 0.78`) with cursor exit hysteresis (debounced hover to prevent accidental collapses).

---

## 🏗 System Architecture & File Layout

```
Sleepy-Notch/
├── .gitignore                          # Standard macOS, Xcode, SPM ignore list
├── Package.swift                       # Swift Package Manager manifest (macOS v13+)
├── README.md                           # Project specification and developer guide
└── Sources/
    └── SleepyNotch/
        ├── App/
        │   ├── SleepyNotchApp.swift    # Custom @MainActor entry point (.accessory app)
        │   └── AppDelegate.swift       # App lifecycle, NSStatusItem menu bar fallback
        │
        ├── Core/
        │   ├── Models/
        │   │   └── TrackInfo.swift     # Immutable playback data model & source enum
        │   └── Support/                # Notch geometry constants, time formatting
        │
        ├── Services/
        │   ├── Media/
        │   │   └── PlaybackCoordinator.swift  # Playback observation, AppleScript IPC, artwork cache
        │   ├── IPC/                    # AppleScript execution, running-app detection
        │   └── Window/
        │       ├── NotchWindowController.swift # Frameless NSPanel, notch metrics, screen changes
        │       ├── NotchPanel.swift            # Panel subclass with notch-shaped hit testing
        │       └── NotchGeometryProvider.swift # Notched-display detection
        │
        ├── DesignSystem/                # Shared visuals, reusable across features
        │   ├── NotchShape.swift        # Bezier curve geometry matching physical MacBook notch
        │   ├── WaveformVisualizer.swift# Animated motion indicator bars (not audio-reactive)
        │   └── MarqueeText.swift       # Auto-scrolling label for long song titles
        │
        └── Features/
            ├── Notch/
            │   ├── NotchView.swift     # Root morphing container (switches compact/expanded)
            │   └── CompactNotchView.swift # Collapsed notch wings (mini artwork & waveform)
            └── Player/
                └── ExpandedPlayerView.swift  # Full controller card (scrubber, transport, metadata)
```

**Layering rules** (enforced by convention, see `docs/ARCHITECTURE.md` when added):

1. `Services/` and `Core/` may import Foundation/AppKit/SwiftUI — **never** `Features/` or `DesignSystem/`.
2. `DesignSystem/` holds visuals shared by more than one feature; it imports nothing from `Features/`.
3. `Features/` may import `Core/`, `Services/` and `DesignSystem/`.
4. `App/` is the entry point and owns wiring.

---

## 🔮 Planned Architecture (Proposed Refactor)

> **Status: proposal, not yet implemented.** The tree above documents the *current* layout. The tree below is the *target* layout. Work through the steps in order; each step is a `git mv`-heavy, low-risk change.

### Target Directory Structure

```
Sleepy-Notch/
├── .github/workflows/ci.yml                  NEW
├── .gitignore
├── LICENSE                                    NEW  (MIT — README promises it, file missing)
├── Package.swift                             EDIT (rename product, retarget path)
├── README.md
├── docs/
│   └── ARCHITECTURE.md                       NEW  (layering rules, replaces "DO NOT BREAK")
├── Sources/
│   └── SleepyNotch/
│       ├── App/
│       │   ├── SleepyNotchApp.swift          <- Sources/main.swift
│       │   ├── AppDelegate.swift             <- Sources/AppDelegate.swift (slimmed)
│       │   ├── AppEnvironment.swift          NEW  dependency container
│       │   └── StatusItemController.swift    NEW  extracted from AppDelegate
│       ├── Core/
│       │   ├── Models/
│       │   │   ├── TrackInfo.swift           <- Sources/Models/TrackInfo.swift
│       │   │   └── MusicSource.swift         NEW  split out of TrackInfo.swift
│       │   ├── State/
│       │   │   ├── NotchInteractionState.swift   NEW  lifted from NotchView.swift:4
│       │   │   └── PlayerUIState.swift           NEW  lifted from ExpandedPlayerView.swift:4
│       │   └── Support/
│       │       ├── NotchMetrics.swift       NEW  centralizes 179/32/220/175/735.5
│       │       └── TimeFormatting.swift     NEW  centralizes fmt(_:)
│       ├── Services/
│       │   ├── Media/
│       │   │   ├── PlaybackSource.swift     NEW  protocol
│       │   │   ├── PlaybackCoordinator.swift   <- Services/MediaManager.swift (slimmed)
│       │   │   ├── AppleMusicSource.swift   NEW
│       │   │   ├── SpotifySource.swift      NEW
│       │   │   └── DemoSource.swift         NEW
│       │   ├── IPC/
│       │   │   ├── AppleScriptRunner.swift  NEW
│       │   │   └── RunningAppProbe.swift    NEW
│       │   ├── Artwork/
│       │   │   ├── ArtworkCache.swift       NEW
│       │   │   └── ArtworkLoader.swift      NEW
│       │   └── Window/
│       │       ├── NotchWindowController.swift  <- Services/NotchWindowManager.swift
│       │       ├── NotchPanel.swift             NEW
│       │       └── NotchGeometryProvider.swift  NEW
│       ├── DesignSystem/
│       │   ├── Theme.swift                  NEW  kills 3x duplicated accentColor
│       │   ├── NotchShape.swift             <- Views/NotchShape.swift
│       │   ├── WaveformVisualizer.swift     <- Views/WaveformVisualizer.swift
│       │   ├── WaveformModel.swift          NEW  lifted from WaveformVisualizer.swift:3
│       │   └── MarqueeText.swift            <- Views/MarqueeText.swift
│       └── Features/
│           ├── Notch/
│           │   ├── NotchView.swift          <- Views/NotchView.swift
│           │   └── CompactNotchView.swift   <- Views/CompactNotchView.swift
│           └── Player/
│               ├── ExpandedPlayerView.swift  <- Views/ExpandedPlayerView.swift (orchestrator)
│               ├── ArtworkView.swift        NEW
│               ├── TrackMetadataView.swift  NEW
│               ├── TransportControls.swift  NEW
│               └── PlayerScrubber.swift     NEW
└── Tests/
    └── SleepyNotchTests/
        ├── TrackInfoTests.swift             NEW
        ├── NotchMetricsTests.swift          NEW
        ├── TimeFormattingTests.swift        NEW
        └── PlaybackCoordinatorTests.swift   NEW  (fake PlaybackSource)
```

### Layering Rules This Enforces

1. `Services/` may import `Core/` + Foundation/AppKit — **never** `Features/` or `DesignSystem/`. Fixes the current violation where `NotchWindowManager.swift:81` constructs `NotchView`.
2. `Features/` imports `DesignSystem/` + `Core/` only. Shared visuals (`NotchShape`, `WaveformVisualizer`, `MarqueeText`, `Theme`) move out of `Features/` so they're reusable.
3. `App/` is the only place that wires concrete types together (`AppEnvironment`).
4. One primary type per file.
5. No `public` in a single-module target (currently `public` on everything — pure noise).

### Key Refactors

**`PlaybackSource` protocol** replaces the `if isDemoMode { ... } else { AppleScript }` branching repeated 6x in `MediaManager.swift:189-240`:

```swift
protocol PlaybackSource: AnyObject {
    var kind: MusicSource { get }
    var events: AnyPublisher<TrackInfo, Never> { get }
    func play(); func pause(); func next(); func previous()
    func seek(to seconds: Double)
    func artwork() async -> NSImage?
}
```

`PlaybackCoordinator` owns the active source, the notification observers, and the battery-gated
`progressUpdateTimer` (`MediaManager.swift:250-268`, preserved verbatim). It keeps `static let shared`
for compatibility but gains an injectable `init` so tests can supply a fake.

**Dedup `accentColor`** — identical `switch` at `NotchView.swift:145`, `ExpandedPlayerView.swift:304`,
`CompactNotchView.swift:84` collapses to one `Theme.accent(for: MusicSource)`.

**Delete dead code** — `MediaManager.isHovered` (superseded by `NotchInteractionState`) and
`MediaManager.volume` (never read).

**Invert the `NotchView` dependency** — `NotchView.init(playback:notchWidth:notchHeight:)` becomes
explicit instead of defaulting to `MediaManager.shared`; `NotchWindowController` receives a
`() -> AnyView` provider from `AppEnvironment`.

### Known Build Defect

`Sources/main.swift` declares `@main struct AppMain`. A file named `main.swift` *is* the top-level-code
file, so Swift rejects this: *"'main' attribute cannot be used in a module that contains top-level
code."* Renaming the file to `SleepyNotchApp.swift` is a **fix**, not cosmetics. Confirm with
`swift build` before starting (Step 2) — the project may not compile at all today.

### Open Question

`TrackInfo` declares `Sendable` but carries `NSImage?`, which is not `Sendable` — the conformance is
technically a lie. Harmless in Swift 5 language mode; it becomes an error under Swift 6.
Decision needed: drop the `Sendable` conformance, or keep it and document the debt in
`docs/ARCHITECTURE.md`.

### Steps

1. **Commit the current staged state first** so `git mv` produces clean renames.
2. `swift build` to establish whether the `@main`/`main.swift` conflict is real.
3. Create the `Sources/SleepyNotch/` tree; `git mv` all 12 existing files per the mapping above.
4. Edit `Package.swift`: product/target -> `SleepyNotch`, `path: "Sources/SleepyNotch"`, add `testTarget`. Keep `swift-tools-version: 5.9` (bumping to 6 forces strict concurrency — out of scope).
5. Do the code refactors above, smallest-file-first, building after each layer.
6. Add `Tests/SleepyNotchTests` + the `Package.swift` test target; `swift test`.
7. Add `.github/workflows/ci.yml` (macos-14, `swift build`, `swift test`).
8. Add `LICENSE` (MIT, per the License section below).
9. Rewrite the "System Architecture & File Layout" section above to match the shipped layout; add `docs/ARCHITECTURE.md` with the layering rules.
10. Final: `swift build -c release` + `swift test`.

### Verification

- `swift build` clean, zero warnings
- `swift test` green
- `swift build -c release` -> `.build/release/SleepyNotch`
- Manual: demo mode via `d`, hover-expand, pin, play/pause, seek drag, and the no-notch fallback path on an external display

### Non-Goals

- No visual/behavior change to the HUD, animations, or spring constants
- No Swift 6 language mode / strict concurrency migration
- No `Info.plist`/entitlements/bundle — still a bare `swift run` executable
- No multi-module SPM split

---

## 🧩 Architectural Breakdown (For AI & Developers)

### 1. `MediaManager.swift` — Zero-Polling Event Pipeline
- Subscribes once to `DistributedNotificationCenter`:
  - `com.apple.Music.playerInfo` (Apple Music)
  - `com.spotify.client.PlaybackStateChanged` (Spotify)
- **Battery Optimization:** There is no progress timer on the coordinator. The scrubber in the expanded card owns a `TimelineView` driven by `PlaybackClockSchedule`, which ticks once per second of playback and yields nothing while paused or while `PowerStateMonitor.isNotchVisible` is false. Only the scrubber redraws.
- **AppleScript IPC:** Playback control commands (`playpause`, `next track`, `previous track`, `set player position`) execute asynchronously on a background queue (`DispatchQueue.global(qos: .userInitiated)`) to ensure the main thread never hitches.
- **Artwork Cache:** `NSCache<NSString, NSImage>` stores fetched artwork in memory to avoid repetitive disk or AppleScript IPC queries.

### 2. `NotchWindowManager.swift` — Notch Geometry & Panel Management
- Uses a borderless, transparent `NSPanel` with `.floating` window level and `.canJoinAllSpaces`.
- Detects the physical notch on modern MacBooks using `screen.auxiliaryTopLeftArea` and `screen.auxiliaryTopRightArea`. If no notch exists (e.g., external displays), it falls back to a clean floating pill below the menu bar.
- Implements `NSTrackingArea` with debounced mouse exit (`0.25s` delay) to prevent erratic collapse when moving the cursor across UI elements.

### 3. `NotchShape.swift` & `Views/` — Spring Physics & Rendering
- **`NotchShape`:** Custom SwiftUI `Shape` implementing smooth continuous corner radii matching Apple's hardware notch silhouette.
- **`CompactNotchView`:** Left wing displays 16x16 rounded album artwork and a truncated title; right wing displays still waveform bars (raised while playing, flat when paused). Nothing in the collapsed view animates.
- **`ExpandedPlayerView`:**
  - Dynamic gradient glassmorphic card (`Material.ultraThinMaterial`).
  - Interactive scrubber slider supporting tap-to-seek and drag-to-seek.
  - Track info with automatic Marquee scroll for long titles.
  - Transport buttons: Previous (`[`), Play/Pause (`Space`), Next (`]`), and Like/Favorite action target.

---

## ⚡ Battery & Performance Rules (DO NOT BREAK)

When modifying or extending this codebase, **any AI agent or developer MUST adhere to these non-negotiable rules**:

1. **NO POLLING LOOPS:** Never use `Timer.scheduledTimer` or `Task.sleep` to repeatedly poll playback state, position, or volume. Rely solely on notifications and user gestures.
2. **CONDITIONAL ANIMATIONS:** Waveforms, timers, and marquee animations must halt immediately when `isPlaying == false` or `isExpanded == false`. The collapsed notch never animates.
3. **BACKGROUND IPC:** Never invoke `NSAppleScript.executeAndReturnError` synchronously on `@MainActor`.
4. **MINIMAL REDRAWS:** Prefer fine-grained `@ObservedObject` or derived states to prevent re-rendering the entire notch hierarchy.
5. **RESPECT POWER STATE:** Gate timers on `PowerStateMonitor.isNotchVisible` (display asleep, locked, hidden) and decorative motion on `allowsDecorativeMotion` (also Low Power Mode and Reduce Motion).
6. **MEASURE IT:** Run `scripts/measure-energy.sh` with music playing and the notch collapsed. Target: ~0% CPU and ~0 idle wake-ups per second.

---

## 🚀 Building & Running

### Prerequisites
- macOS 13.0 (Ventura) or later.
- Xcode 15+ or Swift Command Line Tools (`swift --version` >= 5.9).

### Run in Development Mode
```bash
# Navigate to the project root
cd ~/Projects/Sleepy-Notch

# Run via Swift Package Manager
swift run
```

### Build Optimized Release Binary
```bash
swift build -c release
```
The compiled binary will be located at:
`.build/release/SleepyNotch`

---

## 🎛 Controls & Hotkeys

| Action | Gesture / Shortcut |
| :--- | :--- |
| **Expand Notch HUD** | Hover cursor over camera notch |
| **Open HUD** | Hover over the notch, or click it (closes when the cursor leaves) |
| **Play / Pause** | Click Play button or press `Space` |
| **Next Track** | Click Next button or press `]` |
| **Previous Track** | Click Prev button or press `[` |
| **Seek / Scrub** | Click or drag on the progress bar |
| **Toggle HUD** | Menu bar icon -> Toggle Notch HUD (or `n`) |
| **Toggle Demo Mode** | Menu bar icon -> Toggle Demo Mode (or `d`) |

---

## 🔮 Roadmap & Future AI Extension Guide

When adding new features, maintain compatibility with the existing patterns:
- **❤️ Like / Favorite Button:**
  - *Apple Music:* AppleScript `tell application "Music" to set favorited of current track to true`.
  - *Spotify:* Spotify macOS AppleScript dictionary does not expose track saving directly; integrate with Spotify Web API OAuth token or AppleScript key combinations.
- **Lyrics View:** Add an expandable bottom sheet using LRC synchronization, active only when expanded.
- **Display Selection:** Multi-monitor support to choose between primary MacBook display notch vs. external screen HUD.
- **AirPlay / Volume Slider:** Gesture-based volume slide on hover scroll wheel.

---

## 📜 License
MIT License. Crafted for high performance and clean macOS aesthetics.
