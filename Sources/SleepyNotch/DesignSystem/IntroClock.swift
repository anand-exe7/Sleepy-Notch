import Foundation

/// The time base for an intro drawn frame by frame: a one-shot clock that
/// runs for as long as the intro needs and then stops, so nothing ticks once
/// it has settled.
///
/// Views read `time(at:)` inside a `TimelineView` that's paused whenever the
/// clock isn't running. Before it starts, time is 0 (the intro's first frame);
/// once it has finished, time is far in the future (every curve settled).
@MainActor
final class IntroClock: ObservableObject {
    @Published private(set) var isRunning = false
    /// Seconds since the start at which a later stage begins — e.g. battery
    /// rings filling once the levels arrive. Infinite until then.
    @Published private(set) var marks: [String: Double] = [:]

    private var start: Date?
    private var finished = false
    private var stopWork: DispatchWorkItem?

    /// Seconds since the intro began, as the scene should draw them.
    func time(at date: Date) -> Double {
        if finished { return 1_000 }
        guard let start else { return 0 }
        return date.timeIntervalSince(start)
    }

    func mark(_ name: String) -> Double {
        marks[name] ?? .infinity
    }

    /// Starts the intro, running until `end` seconds in.
    func run(until end: Double) {
        start = Date()
        finished = false
        isRunning = true
        scheduleStop(at: end)
    }

    /// Starts a later stage `name` now (or at `earliest`, if that's later)
    /// and keeps the clock running `duration` past it.
    func begin(_ name: String, earliest: Double, duration: Double) {
        guard let start else {
            marks[name] = earliest
            return
        }
        let now = Date().timeIntervalSince(start)
        let at = max(earliest, now + 0.05)
        marks[name] = at
        finished = false
        isRunning = true
        scheduleStop(at: at + duration)
    }

    /// Jumps to the settled state, e.g. with Reduce Motion.
    func finish() {
        stopWork?.cancel()
        finished = true
        isRunning = false
    }

    private func scheduleStop(at end: Double) {
        stopWork?.cancel()
        guard let start else { return }
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        stopWork = work
        let delay = max(0, end - Date().timeIntervalSince(start))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Curves for intros drawn from an `IntroClock`: each gives progress at time
/// `t`, in seconds since the intro began, 0 before `start`. Plain functions
/// of time, so a scene can be drawn at any moment.
enum IntroCurve {
    /// A damped spring settling from 0 to 1. Below a damping of 1 it
    /// overshoots before settling — the pop.
    static func spring(_ t: Double, start: Double, response: Double = 0.5, damping: Double = 0.7) -> Double {
        let x = t - start
        guard x > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        guard damping < 1 else { return 1 - (1 + omega * x) * exp(-omega * x) }
        let decay = damping * omega
        let ringing = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-decay * x) * (cos(ringing * x) + decay / ringing * sin(ringing * x))
    }

    /// Fast start, gentle landing.
    static func easeOut(_ t: Double, start: Double, duration: Double) -> Double {
        let p = linear(t, start: start, duration: duration)
        return 1 - pow(1 - p, 3)
    }

    static func linear(_ t: Double, start: Double, duration: Double) -> Double {
        guard start.isFinite else { return 0 }
        return min(max((t - start) / duration, 0), 1)
    }

    /// 0 → 1 → 0 over `duration`: a one-off bump.
    static func bump(_ t: Double, start: Double, duration: Double) -> Double {
        sin(Double.pi * linear(t, start: start, duration: duration))
    }
}
