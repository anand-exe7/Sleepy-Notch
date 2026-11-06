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

    private func start() {
        guard process == nil else { return }
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
                self?.startedAt = nil
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
        startedAt = nil
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
        let started = line[range.upperBound...].first == "1"
        // The tag just before "hasStarted=": the capture's own address.
        let before = line[..<range.lowerBound].split(separator: " ").last.map(String.init) ?? "?"
        // The system logs the same event twice (once from a block); a
        // repeat changes nothing.
        if started {
            if active.insert(before).inserted, startedAt == nil { startedAt = Date() }
        } else {
            active.remove(before)
            if active.isEmpty { startedAt = nil }
        }
    }

    /// Pretend a recording started or ended, for the Feature Lab.
    func simulate(_ on: Bool) {
        startedAt = on ? Date() : nil
        if !on { active = [] }
    }
}
