import Foundation

/// The 20-20-20 eye-break reminder: one pending timer, set again each time
/// it fires.
///
/// It only runs while it is wanted (the Settings switch is on) and the
/// screen is in use: when the screen locks, the display sleeps or the
/// session changes it is cancelled outright, and coming back starts a fresh
/// interval. Nothing runs between the timer's firing and its next arming.
@MainActor
final class EyeBreakScheduler {
    /// Called when a break is due.
    var onDue: (() -> Void)?
    /// Time between breaks. The 20-20-20 rule says twenty minutes.
    var interval: TimeInterval = 20 * 60

    private var work: DispatchWorkItem?
    private(set) var isRunning = false

    /// Runs while `running`, and stops (and forgets the interval) otherwise.
    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running { arm() } else { disarm() }
    }

    private func arm() {
        work?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.onDue?()
            self.arm()
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    private func disarm() {
        work?.cancel()
        work = nil
    }
}
