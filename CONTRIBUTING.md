# Contributing to Sleepy Notch

Thanks for wanting to help. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/anand-exe7/Sleepy-Notch/issues/new/choose) and pick **Bug report** or **Feature request**. For bugs, the form asks for your macOS version and Mac model: many notch problems only happen on one screen size, so they help a lot.

## Getting set up

You need macOS 13 or later and the Swift toolchain (Xcode, or just the Command Line Tools with Swift 5.9+).

```bash
git clone https://github.com/anand-exe7/Sleepy-Notch.git
cd Sleepy-Notch
swift run
```

`swift run` builds a development version: the menu bar shows **🧪 Feature Lab**, which can simulate every notice and activity (charging, AirPods, a meeting, an agent needing you) so you don't have to wait for the real thing.

To test anything that needs a permission (Calendar, Microphone, Automation, Accessibility), build the real app, because a bare `swift run` doesn't get macOS's permission prompts:

```bash
scripts/make-app.sh
open "build/Sleepy Notch.app"
```

Only one copy can run at a time, so quit one before starting the other.

## How the code is laid out

```
Sources/SleepyNotch/
├── App/            Entry point and wiring (AppEnvironment, AppWiring)
├── Core/           Models and small helpers, no UI
├── Services/       Music sources, system monitors, the notch window
├── DesignSystem/   Shared visuals
└── Features/       Notch, Player, Peeks, Activities, Shelf, Settings, …
```

- `Core/` and `Services/` never import `Features/` or `DesignSystem/`; `DesignSystem/` never imports `Features/`.
- `App/` is the only place concrete types are wired together.
- One main type per file. No `public` (it's a single module).

## The rules that keep it light

Sleepy Notch is meant to cost nothing while you're not looking at it. Please keep to these:

1. **No polling, no repeating timers.** Use system notifications (DistributedNotificationCenter, IOKit, CoreAudio, EventKit, …) and one-shot timers.
2. **Nothing animates once it has settled**, and everything stops while nobody can see it (display asleep, screen locked, notch hidden). Check `PowerStateMonitor.isNotchVisible` and `allowsDecorativeMotion`.
3. **Looping motion goes to Core Animation**, not a SwiftUI `TimelineView` or a timer, so the window server runs it and the app does nothing per frame.
4. **Every feature is a switch in Settings** and costs nothing when it's off.
5. **AppleScript never runs on the main thread.**
6. **Newer macOS APIs go behind `#available`**; the app supports macOS 13. Private APIs load through `dlsym`, and a missing symbol turns the feature off quietly.

Measure before and after a change that could cost battery:

```bash
scripts/measure-energy.sh 30
```

With the notch closed and music playing it should stay at about 0% CPU and 0 wake-ups a second.

## Look and feel

Apple-native: San Francisco, colour only where it means something (status), no glows or looping decoration. Things rise in on a gentle curve and play once.

## Sending a pull request

1. Fork the repo and make a branch for your change (`fix/shelf-drop`, `feature/weather`).
2. Keep each pull request to one change, and say what it does and how you tested it.
3. Make sure `swift build` passes, and add a screenshot for anything visual.
4. Open the pull request against `main`.

## Licence

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
