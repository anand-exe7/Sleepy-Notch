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
    static func start(window: NotchWindowController, playback: PlaybackCoordinator) {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["SLEEPY_BENCH"], !mode.isEmpty else { return }
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
            case "hold":
                window.benchSetPointerInside(true)
            case "cycles":
                step(window: window, inside: true)
            case "shots":
                shoot(window: window)
            default:
                // "idle": the demo song alone.
                break
            }
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
        guard let out = ProcessInfo.processInfo.environment["SLEEPY_BENCH_OUT"],
              let (number, frame) = window.benchWindow(),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.benchSetPointerInside(true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { window.benchSetPointerInside(false) }
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
