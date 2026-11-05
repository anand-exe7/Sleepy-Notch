import AppKit
import SwiftUI

// TEMPORARY: frame-by-frame capture of the closed notch's bubbles. Not to be
// committed.
@MainActor
enum CaptureHarness {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func runIfRequested(_ env: AppEnvironment) {
        guard let dir = ProcessInfo.processInfo.environment["SLEEPY_CAPTURE"] else { return }
        let only = ProcessInfo.processInfo.environment["SLEEPY_CAPTURE_ONLY"]
        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            @MainActor func play() {
                var track = env.playback.currentTrack
                track.isPlaying = true
                env.playback.currentTrack = track
            }
            @MainActor func step(_ name: String, _ seconds: Double = 1.3, _ change: @escaping @MainActor () -> Void) async {
                if let only, !only.contains(name.first!) { change(); await wait(seconds); return }
                await capture(name: name, dir: dir, seconds: seconds, change: change)
            }
            await wait(2.5)
            env.powerSource.onSnapshot = nil
            env.status.chargingLevel = nil
            env.status.micInUse = false
            env.status.cameraInUse = false
            env.playback.advanceDemoSong()
            await wait(1.5)
            play()
            await wait(1.2)

            await step("1-charge-split") { env.status.chargingLevel = 72 }
            await step("2-mic-split") { env.status.micInUse = true }
            await step("3-camera-join") { env.status.cameraInUse = true }
            await step("4-charge-merge") { env.status.chargingLevel = nil }
            await step("5-privacy-merge") {
                env.status.micInUse = false
                env.status.cameraInUse = false
            }
            env.status.chargingLevel = 72
            await wait(1.2)
            await step("6-music-stops") { env.playback.currentTrack = TrackInfo() }
            await step("7-music-back", 1.8) {
                env.playback.advanceDemoSong()
            }
            play()
            env.status.micInUse = true
            await wait(1.5)
            await step("8-card-open", 1.2) { env.window.debugHover(true) }
            await step("9-card-close", 2.0) { env.window.debugHover(false) }
            exit(0)
        }
    }

    private static func capture(name: String, dir: String, seconds: Double, change: @escaping @MainActor () -> Void) async {
        guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible && $0.frame.width > 300 }),
              let screen = panel.screen ?? NSScreen.screens.first,
              let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { print("capture: no panel"); return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let frame = panel.frame
        let height: CGFloat = 44
        let width: CGFloat = 420
        let rect = CGRect(x: frame.midX - width / 2, y: primaryHeight - frame.maxY, width: width, height: height)
        let id = UInt32(panel.windowNumber)

        var frames: [CGImage] = []
        let start = Date()
        var changed = false
        while Date().timeIntervalSince(start) < seconds {
            if !changed && Date().timeIntervalSince(start) > 0.05 {
                changed = true
                change()
            }
            if let image = create(rect, 1 << 3, id, 1 << 0)?.takeRetainedValue() {
                frames.append(image)
            }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        let pageSize = 12
        let columns = 2
        let w = Int(width * 2), h = Int(height * 2)
        for page in stride(from: 0, to: frames.count, by: pageSize) {
            let slice = Array(frames[page..<min(frames.count, page + pageSize)])
            let rows = (slice.count + columns - 1) / columns
            let size = NSSize(width: w * columns, height: h * rows)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(white: 0.62, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            for (k, frame) in slice.enumerated() {
                let col = k % columns, row = k / columns
                let r = NSRect(x: col * w, y: (rows - 1 - row) * h, width: w, height: h)
                NSGraphicsContext.current?.cgContext.interpolationQuality = .high
                NSGraphicsContext.current?.cgContext.draw(frame, in: r)
                NSString(string: "\(page + k)").draw(at: NSPoint(x: r.minX + 4, y: r.minY + 2), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white
                ])
                NSColor(white: 0.45, alpha: 1).setFill()
                NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
                NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
            }
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let file = String(format: "%@-p%02d.png", name, page / pageSize)
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
        }
        print("capture \(name): \(frames.count) frames in \(seconds)s")
    }
}
