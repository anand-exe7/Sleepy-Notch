import AppKit

/// One running countdown.
struct TimerSession: Equatable {
    let start: Date
    let end: Date
    /// A sleep timer: it fades the music out at the end instead of ringing.
    var sleeps = false

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A countdown the user starts from the menu bar and sees as a live
/// activity beside the notch. A sleep timer is the same countdown, and when
/// it ends the music fades out and pauses.
///
/// The time on screen is drawn by the system from the end date (the text
/// counts down by itself and the ring is one Core Animation animation), so
/// nothing here ticks. The only timer is a single one-shot for the moment
/// it ends. The fade is one `osascript` process that waits, steps the
/// player's volume down, pauses and puts the volume back: the app itself
/// does nothing while it runs.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var session: TimerSession?

    /// Off in Settings: nothing starts, and a running timer is cancelled.
    var isEnabled = true {
        didSet { if !isEnabled { cancel() } }
    }
    /// Called with the length of the timer that just finished, and whether
    /// it was a sleep timer.
    var onFinish: ((TimeInterval, Bool) -> Void)?

    private var finishWork: DispatchWorkItem?

    // The sleep timer's fade.
    private var fade: Process?
    private var fadeApp: String?
    /// The volume the fade started from, once it has begun.
    private var volumeBeforeFade: Int?

    /// How long the fade takes at the end.
    static let fadeDuration: TimeInterval = 30

    func start(minutes: Double) {
        begin(duration: minutes * 60, sleeps: false)
    }

    /// Fades `app` ("Music" or "Spotify") out over the last `fadeDuration`
    /// seconds, then pauses it.
    func startSleep(minutes: Double, app: String) {
        startSleep(duration: minutes * 60, app: app, fadeDuration: Self.fadeDuration)
    }

    func startSleep(duration: TimeInterval, app: String, fadeDuration: TimeInterval) {
        guard isEnabled, duration > 0 else { return }
        cancel()
        let fadeLength = min(fadeDuration, duration / 2)
        begin(duration: duration, sleeps: true)
        launchFade(app: app, wait: duration - fadeLength, fade: fadeLength)
    }

    private func begin(duration: TimeInterval, sleeps: Bool) {
        guard isEnabled, duration > 0 else { return }
        if !sleeps { cancel() }
        finishWork?.cancel()
        let now = Date()
        let session = TimerSession(start: now, end: now.addingTimeInterval(duration), sleeps: sleeps)
        self.session = session
        let work = DispatchWorkItem { [weak self] in self?.finish(session) }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func cancel() {
        let wasFading = volumeBeforeFade
        let app = fadeApp
        stopFade()
        finishWork?.cancel()
        finishWork = nil
        session = nil
        // Cancelled part-way down: put the volume back where it was.
        if let wasFading, let app { Self.setVolume(wasFading, of: app) }
    }

    /// The app is quitting: stop the fade, and put the volume back before
    /// the process is gone (a sleeping task would never run).
    func cancelForQuit() {
        let wasFading = volumeBeforeFade
        let app = fadeApp
        stopFade()
        finishWork?.cancel()
        finishWork = nil
        session = nil
        guard let wasFading, let app else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "if application \"\(app)\" is running then tell application \"\(app)\" to set sound volume to \(wasFading)"]
        try? process.run()
        process.waitUntilExit()
    }

    /// The user paused the music themselves: a sleep timer has no more to do.
    func playbackPausedByUser() {
        guard session?.sleeps == true else { return }
        cancel()
    }

    private func finish(_ finished: TimerSession) {
        guard session == finished else { return }
        finishWork = nil
        session = nil
        // The fade has put the volume back by now (or never began).
        volumeBeforeFade = nil
        fade = nil
        fadeApp = nil
        if !finished.sleeps { NSSound(named: NSSound.Name("Glass"))?.play() }
        onFinish?(finished.duration, finished.sleeps)
    }

    // MARK: - The fade

    /// One process: wait, read the volume, step it down, pause, restore it.
    private func launchFade(app: String, wait: TimeInterval, fade length: TimeInterval) {
        let steps = max(5, Int(length.rounded()))
        let script = """
        delay \(wait)
        if application "\(app)" is running then
            tell application "\(app)"
                set startVolume to sound volume
                log "START " & startVolume
                repeat with i from 1 to \(steps)
                    set sound volume to (startVolume * (\(steps) - i) / \(steps)) as integer
                    log "VOL " & (sound volume)
                    delay \(length / Double(steps))
                end repeat
                pause
                set sound volume to startVolume
                log "RESTORED " & (sound volume)
            end tell
        end if
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        // Called when the script writes a line: no polling.
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            for line in text.split(separator: "\n") {
                if let value = line.split(separator: " ").last.flatMap({ Int($0) }), line.hasPrefix("START") {
                    Task { @MainActor [weak self] in self?.volumeBeforeFade = value }
                } else if line.hasPrefix("RESTORED") {
                    Task { @MainActor [weak self] in self?.volumeBeforeFade = nil }
                }
            }
        }
        do {
            try process.run()
            fade = process
            fadeApp = app
            volumeBeforeFade = nil
        } catch {
            fade = nil
        }
    }

    private func stopFade() {
        if let fade, fade.isRunning { fade.terminate() }
        fade = nil
        fadeApp = nil
        volumeBeforeFade = nil
    }

    private static func setVolume(_ volume: Int, of app: String) {
        let script = "if application \"\(app)\" is running then tell application \"\(app)\" to set sound volume to \(volume)"
        Task { _ = try? await AppleScriptRunner.shared.run(script) }
    }
}
