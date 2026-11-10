import Foundation

/// A Pomodoro cycle on the notch's own timer: focus, then a short break (a
/// long one after every fourth round), the next round started by the user.
///
/// It adds nothing that runs: the countdown is the timer's (drawn by the
/// system from its end date, one one-shot at the end). When a focus round
/// ends the break starts by itself, so the count and the rhythm hold even if
/// you step away; when a break ends it stops and waits.
@MainActor
final class PomodoroService: ObservableObject {
    /// Focus rounds finished today.
    @Published private(set) var completedToday = 0

    var focusMinutes: Double = 25
    static let shortBreak: Double = 5
    static let longBreak: Double = 15
    private static let roundsBeforeLongBreak = 4

    /// What to say when a round ends.
    var onNotice: ((String) -> Void)?

    private let timers: TimerService
    private var countedOn = Calendar.current.startOfDay(for: Date())

    init(timers: TimerService) {
        self.timers = timers
        timers.onPomodoroFinish = { [weak self] phase in self?.finished(phase) }
    }

    /// The running round, if the timer is one.
    var phase: PomodoroPhase? { timers.session?.pomodoro }

    /// Starts a focus round (replacing a running Pomodoro round).
    func startFocus() {
        rollOverDay()
        timers.startPomodoro(.focus, minutes: focusMinutes)
    }

    /// Ends the current round now: a focus round counts as done, and the
    /// break follows, as if it had run out.
    func skip() {
        guard let phase else { return }
        timers.cancel()
        finished(phase, silent: true)
    }

    func stop() {
        guard phase != nil else { return }
        timers.cancel()
    }

    private func rollOverDay() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != countedOn {
            countedOn = today
            completedToday = 0
        }
    }

    private func finished(_ phase: PomodoroPhase, silent: Bool = false) {
        rollOverDay()
        switch phase {
        case .focus:
            completedToday += 1
            let long = completedToday % Self.roundsBeforeLongBreak == 0
            let minutes = long ? Self.longBreak : Self.shortBreak
            timers.startPomodoro(.rest, minutes: minutes)
            if !silent {
                onNotice?(long ? "Focus done. Take a long break: \(Int(minutes)) minutes" : "Focus done. Break for \(Int(minutes)) minutes")
            }
        case .rest:
            if !silent { onNotice?("Break over. Ready for the next round?") }
        }
    }
}
