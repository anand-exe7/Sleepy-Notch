import SwiftUI

/// Drives the scrubber: one tick per second of playback, landing exactly when
/// the elapsed-time label should change.
///
/// Only the scrubber redraws, once a second, instead of a timer re-rendering
/// the whole notch. Inactive — paused, or nobody can see the card — the
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

    /// The first whole second of playback after `date`.
    func nextTick(after date: Date) -> Date {
        // The small epsilon stops floating-point error from producing the
        // same date twice when `date` already sits on a whole second.
        anchor.addingTimeInterval((date.timeIntervalSince(anchor) + 0.001).rounded(.down) + 1)
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
