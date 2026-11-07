import Foundation

/// Tells the notch when the screen is being recorded, and since when, for a
/// running time beside the notch.
///
/// macOS has no notification for it, but the system logs it: while a screen
/// capture runs, `replayd` (the service behind ScreenCaptureKit, which every
/// recorder uses: Screenshot's recorder, QuickTime Player, other apps)
/// writes "updateScreenCaptureDidStart … hasStarted=1" when one begins and
/// "hasStarted=0" when it ends. `log stream` with a predicate for just those
/// lines is a child process that only wakes when one is written, and costs
/// next to nothing. No permission is needed.
///
/// A recording that was already running when the app started isn't seen
/// until the next one: there is no state to ask, only events.
@MainActor
final class ScreenRecordingMonitor: ObservableObject {
    /// When the current recording began, or nil when none is running.
    @Published private(set) var startedAt: Date?

    private var process: Process?
    private var pending = ""
    /// Captures that are running now, by the tag the system gives each.
    private var active: Set<String> = []

    private static let predicate = #"process == "replayd" AND eventMessage CONTAINS "updateScreenCaptureDidStart" AND eventMessage CONTAINS "hasStarted=""#

    func setRunning(_ on: Bool) {
        if on { start() } else { stop() }
    }

    /// A recording that has gone on this long is taken to be a missed "ended"
    /// line (the log's wording may change), so the red dot doesn't stay forever.
    private static let staleAfter: TimeInterval = 12 * 3600
    private var staleTimer: Timer?

    /// A `log stream` left behind by an earlier run that was killed or
    /// crashed (it has no parent any more, so only the next run can end it).
    /// Matches only our own predicate, and only children of launchd.
    private static func endOrphans() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-P", "1", "-f", "log stream .*updateScreenCaptureDidStart"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private func start() {
        guard process == nil else { return }
        Self.endOrphans()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--style", "compact", "--level", "info", "--predicate", Self.predicate]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        // Called when the log writes a line: nothing is polled.
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.receive(text) }
        }
        // If `log` ends (it shouldn't), the recording state is unknown.
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.process = nil
                self?.active = []
                self?.setStart(nil)
            }
        }
        do {
            try task.run()
            process = task
        } catch {
            process = nil
        }
    }

    private func stop() {
        if let handle = (process?.standardOutput as? Pipe)?.fileHandleForReading { handle.readabilityHandler = nil }
        process?.terminationHandler = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        pending = ""
        active = []
        setStart(nil)
    }

    /// Sets when the recording began, and the one-shot that gives up on it.
    private func setStart(_ date: Date?) {
        startedAt = date
        staleTimer?.invalidate()
        staleTimer = nil
        guard date != nil else { return }
        let timer = Timer(timeInterval: Self.staleAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = []
                self?.setStart(nil)
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }

    // MARK: - Reading the stream

    private func receive(_ text: String) {
        pending += text
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending = String(pending[pending.index(after: newline)...])
            handle(line: line)
        }
        if pending.count > 8192 { pending = "" }
    }

    /// One log line: "... updateScreenCaptureDidStart:…:165 0x7a0ce3cf60 hasStarted=1".
    func handle(line: String) {
        guard line.contains("updateScreenCaptureDidStart"),
              let range = line.range(of: "hasStarted=") else { return }
        // Only a clear 1 or 0 counts. If the wording ever changes, the line
        // is ignored rather than guessed at (the dot just doesn't show).
        let flag = line[range.upperBound...].first
        guard flag == "1" || flag == "0" else { return }
        let started = flag == "1"
        // The tag just before "hasStarted=": the capture's own address.
        let before = line[..<range.lowerBound].split(separator: " ").last.map(String.init) ?? "?"
        // The system logs the same event twice (once from a block); a
        // repeat changes nothing.
        if started {
            if active.insert(before).inserted, startedAt == nil { setStart(Date()) }
        } else {
            active.remove(before)
            if active.isEmpty { setStart(nil) }
        }
    }

    /// Pretend a recording started or ended, for the Feature Lab.
    func simulate(_ on: Bool) {
        setStart(on ? Date() : nil)
        if !on { active = [] }
    }
}
