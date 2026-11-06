import AppKit

/// One running countdown.
struct TimerSession: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A countdown the user starts from the menu bar and sees as a live
/// activity beside the notch.
///
/// The time on screen is drawn by the system from the end date (the text
/// counts down by itself and the ring is one Core Animation animation), so
/// nothing here ticks. The only timer is a single one-shot for the moment
/// it ends.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var session: TimerSession?

    /// Off in Settings: nothing starts, and a running timer is cancelled.
    var isEnabled = true {
        didSet { if !isEnabled { cancel() } }
    }
    /// Called with the length of the timer that just finished.
    var onFinish: ((TimeInterval) -> Void)?

    private var finishWork: DispatchWorkItem?

    func start(minutes: Double) {
        guard isEnabled, minutes > 0 else { return }
        finishWork?.cancel()
        let now = Date()
        let session = TimerSession(start: now, end: now.addingTimeInterval(minutes * 60))
        self.session = session
        let work = DispatchWorkItem { [weak self] in self?.finish(session) }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + minutes * 60, execute: work)
    }

    func cancel() {
        finishWork?.cancel()
        finishWork = nil
        session = nil
    }

    private func finish(_ finished: TimerSession) {
        guard session == finished else { return }
        finishWork = nil
        session = nil
        NSSound(named: NSSound.Name("Glass"))?.play()
        onFinish?(finished.duration)
    }
}
