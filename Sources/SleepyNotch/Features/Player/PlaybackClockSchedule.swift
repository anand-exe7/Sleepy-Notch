import SwiftUI

/// Drives the scrubber: one tick per second of playback, landing exactly when
/// the elapsed-time label should change.
///
/// This replaces a 0.5s `Timer` on `PlaybackCoordinator` that fired
/// `objectWillChange` and re-rendered the whole notch twice a second. Now only
/// the scrubber redraws, half as often. Inactive — paused, or nobody can see
/// the card — the schedule yields a single entry and then nothing, so there
/// are no wake-ups at all.
struct PlaybackClockSchedule: TimelineSchedule, Equatable {
    /// A wall-clock moment at which playback sat on a whole second.
    let anchor: Date
    let isActive: Bool

    init(track: TrackInfo, isActive: Bool) {
        let fraction = track.position - track.position.rounded(.down)
        anchor = track.lastUpdated.addingTimeInterval(-fraction)
        self.isActive = isActive
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator { [anchor, isActive] in
            guard let current = next else { return nil }
            // The small epsilon stops floating-point error from producing the
            // same date twice when `current` already sits on a whole second.
            next = isActive
                ? anchor.addingTimeInterval((current.timeIntervalSince(anchor) + 0.001).rounded(.down) + 1)
                : nil
            return current
        }
    }
}
