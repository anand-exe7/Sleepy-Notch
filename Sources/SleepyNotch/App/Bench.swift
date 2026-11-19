import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A measuring hook for development only. With `SLEEPY_BENCH` set in the
/// environment the HUD drives itself, so CPU and energy can be read from
/// the outside without a hand on the mouse (synthetic pointer events need
/// Accessibility, which a shell doesn't have):
///
/// - `SLEEPY_BENCH=cycles`: opens and closes the card every 1.5 s.
/// - `SLEEPY_BENCH=hold`: opens the card and leaves it open.
/// - `SLEEPY_BENCH=shots`: photographs the HUD's own window as fast as it
///   can through one open and one close, and writes the frames as PNGs to
///   `SLEEPY_BENCH_OUT` with a `frames.txt` of their times, so the motion
///   can be checked frame by frame and dropped frames counted.
///
/// With `SLEEPY_BENCH_DEMO=1` as well, a demo song "plays" (the clock runs
/// and the bars dance) without touching Music or Spotify, so runs compare
/// whatever the user is listening to.
///
/// Does nothing unless the variable is set. Only one-shot timers.
@MainActor
enum Bench {
    /// `SLEEPY_BENCH_TAB` = shelf, widgets or controls: the page the card
    /// opens on, so each page can be photographed.
    static let startTab: CardTab? = {
        switch ProcessInfo.processInfo.environment["SLEEPY_BENCH_TAB"] {
        case "shelf": return .shelf
        case "widgets": return .widgets
        case "controls": return .controls
        default: return nil
        }
    }()

    /// `SLEEPY_BENCH_DROP=1`: plays a file drag for the frames: the dragged
    /// files come near the notch as the card first opens and over the drop zone 0.6 s later
    /// (the `SLEEPY_BENCH_FILES` stand in for them).
    static let dropDemo = ProcessInfo.processInfo.environment["SLEEPY_BENCH_DROP"] == "1"
    static var dropDemoPlayed = false

    static func start(
        window: NotchWindowController,
        playback: PlaybackCoordinator,
        lockScreen: LockScreenController,
        shelf: ShelfStore,
        agents: AgentStatusService? = nil,
        activities: ActivityManager? = nil
    ) {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["SLEEPY_BENCH"], !mode.isEmpty else { return }
        notch = window
        if mode == "onboarding" { return }
        // `SLEEPY_BENCH_FILES` = paths joined by ":": put on the shelf, so
        // it can be photographed with files on it.
        if let files = environment["SLEEPY_BENCH_FILES"] {
            shelf.add(files.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if environment["SLEEPY_BENCH_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                playback.advanceDemoSong()
                playback.currentTrack.isPlaying = true
                playback.currentTrack.lastUpdated = Date()
            }
        }
        // Let the launch settle: the welcome plays for about eight seconds
        // and holds hover off until it has folded away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            switch mode {
            case "agent":
                // The agent's notices, wings and opened card in each state,
                // one still each (`SLEEPY_BENCH=agent`).
                guard let agents, let activities else { return }
                // The real pointer may rest on the notch: ignore it.
                window.benchSetPointerInside(false)
                let steps: [(AgentState, AgentKind, Bool)] = [
                    (.working, .claude, false), (.needsInput, .claude, false), (.done, .claude, false),
                    (.working, .claude, false), (.done, .claude, true),
                    (.working, .gemini, false), (.working, .codex, false),
                ]
                for (index, step) in steps.enumerated() {
                    let t = Double(index) * 7
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        if index >= 5 { agents.clearSimulated() }
                        agents.simulate(step.0, kind: step.1, stopped: step.2)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.9) { still(window, "\(index)-notice") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t + 4.0) { activities.expand(.agent) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t + 4.9) { still(window, "\(index)-detail") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t + 6.7) { still(window, "\(index)-wings") }
                }
            case "watch":
                // A still every second for 24 s, the agent card opened at
                // 6 s and 16 s: for driving the app from outside (socket
                // events) and seeing what it shows. With
                // `SLEEPY_BENCH_HOLD=1` the card is held open instead, to
                // watch something move in it (the scrolling title).
                if environment["SLEEPY_BENCH_HOLD"] == "1" {
                    window.benchSetPointerInside(true)
                }
                for second in 0..<24 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(second)) {
                        still(window, String(format: "t%02d", second))
                    }
                }
                for second in [6.0, 16.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + second) { activities?.expand(.agent) }
                }
            case "hold":
                window.benchSetPointerInside(true)
            case "cycles":
                step(window: window, inside: true)
            case "shots":
                shoot(window: window)
            case "lock":
                // The lock screen card's preview window, photographed
                // through one open and one close of the pill.
                lockScreen.showPreview()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let target = lockScreen.benchWindow() else { return }
                    shoot(target: target, open: { lockScreen.benchSetExpanded(true) }, close: { lockScreen.benchSetExpanded(false) })
                }
            default:
                // "idle": the demo song alone.
                break
            }
        }
    }

    /// The HUD, for stills taken by the setup's bench.
    private static weak var notch: NotchWindowController?

    /// `SLEEPY_BENCH=onboarding`: walks the setup page by page, a still of
    /// the window on each (`ob-<n>-<page>.png`), the cover change half way
    /// through on the player page, then Start and the notch's hello.
    static func onboarding(window: NSWindow, model: OnboardingModel) {
        guard ProcessInfo.processInfo.environment["SLEEPY_BENCH"] == "onboarding" else { return }
        var t = 3.2
        for step in OnboardingStep.allCases {
            let name = "ob-\(step.rawValue)-\(step)"
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { still(window: window, name) }
            if step == .player {
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.3) { model.playCoverChange() }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.55) { still(window: window, name + "-change") }
                t += 1.2
            }
            if step == .pages {
                // Mid-rise, to see the pieces come in.
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.75) { still(window: window, "ob-2-pages-rise") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.6) {
                if !step.isLast { model.next() }
            }
            t += step.isLast ? 0 : 3.0
        }
        guard ProcessInfo.processInfo.environment["SLEEPY_BENCH_FINISH"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 1.5) { model.next() }
        for (index, delay) in [1.6, 2.6, 4.2].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 1.5 + delay) {
                if let notch { still(notch, "ob-hello-\(index)") }
            }
        }
    }

    /// One picture of an ordinary window, written as `<name>.png`.
    private static func still(window: NSWindow, _ name: String) {
        guard let out = ProcessInfo.processInfo.environment["SLEEPY_BENCH_OUT"],
              let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")
        else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let frame = window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        guard let image = create(rect, 1 << 3, UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue() else { return }
        let folder = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        if let sink = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(sink, image, nil)
            CGImageDestinationFinalize(sink)
        }
    }

    private static func step(window: NotchWindowController, inside: Bool) {
        window.benchSetPointerInside(inside)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            step(window: window, inside: !inside)
        }
    }

    // MARK: - Frames

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func shoot(window: NotchWindowController) {
        guard let target = window.benchWindow() else { return }
        shoot(target: target, open: { window.benchSetPointerInside(true) }, close: { window.benchSetPointerInside(false) })
    }

    /// One picture of the HUD's window, written as `<name>.png`.
    private static func still(_ window: NotchWindowController, _ name: String) {
        guard let (number, frame) = window.benchWindow(),
              let out = ProcessInfo.processInfo.environment["SLEEPY_BENCH_OUT"],
              let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")
        else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        guard let image = create(rect, 1 << 3, UInt32(number), 1 << 3)?.takeRetainedValue() else { return }
        let folder = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        if let sink = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(sink, image, nil)
            CGImageDestinationFinalize(sink)
        }
    }

    private static func shoot(target: (number: Int, frame: CGRect), open: @escaping () -> Void, close: @escaping () -> Void) {
        let (number, frame) = target
        guard let out = ProcessInfo.processInfo.environment["SLEEPY_BENCH_OUT"],
              let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")
        else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // Screen coordinates with the origin at the top left, as CG wants.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        let includingWindow: UInt32 = 1 << 3
        let bestResolution: UInt32 = 1 << 3
        let windowID = UInt32(number)

        var frames: [(time: CFTimeInterval, image: CGImage)] = []
        frames.reserveCapacity(400)
        let capture = DispatchQueue(label: "bench.capture", qos: .userInteractive)
        let start = CACurrentMediaTime()
        let seconds: CFTimeInterval = 2.6
        capture.async {
            while CACurrentMediaTime() - start < seconds {
                let t = CACurrentMediaTime()
                if let image = create(rect, includingWindow, windowID, bestResolution)?.takeRetainedValue() {
                    frames.append((t - start, image))
                }
            }
            DispatchQueue.main.async { write(frames, to: out) }
        }
        // Open at 0.3 s, close at 1.5 s: both motions inside the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: open)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: close)
    }

    private static func write(_ frames: [(time: CFTimeInterval, image: CGImage)], to folder: String) {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var log = ""
        var previous: Data?
        var unique = 0
        for (index, frame) in frames.enumerated() {
            // Same pixels as the frame before: the window server had no new
            // frame for us yet.
            let bytes = (frame.image.dataProvider?.data as Data?) ?? Data()
            let changed = bytes != previous
            previous = bytes
            if changed { unique += 1 }
            log += String(format: "%03d %.4f %@\n", index, frame.time, changed ? "new" : "dup")
            guard changed else { continue }
            let file = url.appendingPathComponent(String(format: "f%03d.png", index))
            if let sink = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(sink, frame.image, nil)
                CGImageDestinationFinalize(sink)
            }
        }
        log += "frames \(frames.count) unique \(unique)\n"
        try? log.write(to: url.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }
}
