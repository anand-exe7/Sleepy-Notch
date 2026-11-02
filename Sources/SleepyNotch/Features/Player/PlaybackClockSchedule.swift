import SwiftUI

/// Drives the scrubber: two ticks per second of playback, one of them landing
/// exactly when the elapsed-time label should change.
///
/// Only the scrubber redraws, twice a second, instead of a timer or an
/// animation re-rendering the whole notch every frame. Inactive — paused, or nobody can see the card — the
/// schedule yields a single entry and then nothing, so there are no
/// wake-ups at all.
struct PlaybackClockSchedule: TimelineSchedule, Equatable {
    /// A wall-clock moment at which playback sat on a whole second.
    let anchor: Date
    let isActive: Bool

    init(track: TrackInfo, isActive: Bool) {
        let fraction = track.position - track.position.rounded(.down)
        anchor = track.lastUpdated.addingTimeInterval(-fraction)
        self.isActive = isActive
    }

    /// Time between ticks, in seconds of playback.
    static let interval: TimeInterval = 0.5

    /// The first tick of playback after `date`: every half second, on the
    /// whole and half seconds.
    func nextTick(after date: Date) -> Date {
        // The small epsilon stops floating-point error from producing the
        // same date twice when `date` already sits on a tick.
        let ticks = ((date.timeIntervalSince(anchor) + 0.001) / Self.interval).rounded(.down) + 1
        return anchor.addingTimeInterval(ticks * Self.interval)
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator { [isActive] in
            guard let current = next else { return nil }
            next = isActive ? nextTick(after: current) : nil
            return current
        }
    }
}
