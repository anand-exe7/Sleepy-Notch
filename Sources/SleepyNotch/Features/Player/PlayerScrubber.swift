import SwiftUI

/// The timeline: elapsed time, the progress bar, remaining time, on one row.
/// The bar glides continuously while a song plays, and thickens when you
/// reach for it, like the system's own scrubbers. Drag or click anywhere on
/// it to seek.
///
/// Battery: the view only re-renders once per second of playback (see
/// `PlaybackClockSchedule`). Between ticks the fill slides with a linear
/// animation timed to land exactly on the next tick, so it moves smoothly
/// without re-rendering every frame. Paused, or while nobody can see the
/// card, nothing runs.
struct PlayerScrubber: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    let accentColor: Color

    @StateObject private var state = ScrubberState()

    private static let timeWidth: CGFloat = 38

    var body: some View {
        let schedule = PlaybackClockSchedule(
            track: media.currentTrack,
            isActive: media.currentTrack.isPlaying && power.isNotchVisible
        )
        TimelineView(schedule) { clock in
            scrubber(at: clock.date, schedule: schedule)
        }
    }

    private var isActive: Bool {
        state.isHovered || state.isDragging
    }

    private func scrubber(at now: Date, schedule: PlaybackClockSchedule) -> some View {
        let track = media.currentTrack
        let position = state.isDragging
            ? state.dragRatio * track.duration
            : track.position(at: now)

        // Where the fill should be, and how to get there: during steady
        // playback it heads for where playback will be at the next tick,
        // arriving just as that tick lands. A new song, a seek or a re-sync
        // springs there instead of sweeping across the bar.
        let target: Double
        let motion: Animation?
        if state.isDragging {
            target = state.dragRatio
            motion = nil
        } else if schedule.isActive {
            let next = schedule.nextTick(after: now)
            target = track.progressRatio(at: next)
            let step = (target - state.lastRatio) * track.duration
            motion = (0...1.5).contains(step)
                ? .linear(duration: max(0.05, next.timeIntervalSince(now)))
                : .spring(response: 0.45, dampingFraction: 0.85)
        } else {
            target = track.progressRatio(at: now)
            motion = .spring(response: 0.4, dampingFraction: 0.85)
        }
        state.lastRatio = target

        return HStack(spacing: 10) {
            Text(TimeFormatting.clock(position))
                .frame(width: Self.timeWidth, alignment: .trailing)

            bar(ratio: target, motion: motion)

            // Whole seconds on both sides, so the two always add up to the
            // track's length instead of the remaining side running a second short.
            Text("-\(TimeFormatting.clock(track.duration.rounded(.down) - position.rounded(.down)))")
                .frame(width: Self.timeWidth, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .medium))
        .monospacedDigit()
        .foregroundColor(isActive ? Theme.Text.secondary : Theme.Text.tertiary)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private func bar(ratio: Double, motion: Animation?) -> some View {
        let height: CGFloat = isActive ? 8 : 5

        return GeometryReader { geo in
            let w = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.22 : 0.16))

                Capsule()
                    .fill(accentColor.opacity(isActive ? 1 : 0.9))
                    .frame(width: max(height, w * min(max(ratio, 0), 1)))
                    .animation(motion, value: ratio)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        state.isDragging = true
                        state.dragRatio = max(0, min(v.location.x / w, 1))
                    }
                    .onEnded { v in
                        media.seek(to: max(0, min(v.location.x / w, 1)))
                        state.isDragging = false
                    }
            )
        }
        // A thin bar is hard to hit, so the target is taller than what's drawn.
        .frame(height: 16)
        .onHover { state.isHovered = $0 }
    }
}

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class ScrubberState: ObservableObject {
    @Published var isDragging = false
    @Published var dragRatio: Double = 0
    @Published var isHovered = false
    /// The fill's last target, to tell a one-second step from a jump. Not
    /// published: it's bookkeeping, not something to redraw for.
    var lastRatio: Double = 0
}
