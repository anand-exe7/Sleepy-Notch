import SwiftUI

/// The timeline: elapsed time, the progress bar, remaining time, on one row.
/// The bar glides continuously while a song plays, and thickens when you
/// reach for it, like the system's own scrubbers. Drag or click anywhere on
/// it to seek.
///
/// Battery: the view re-renders twice per second of playback (see
/// `PlaybackClockSchedule`), and the fill steps to its new spot without an
/// animation. At a song's pace that's a fraction of a point per step, so it
/// still reads as a smooth glide. (A linear animation between ticks was
/// computed on every frame — about 6% CPU for as long as the card sat open
/// with music playing.) Paused, or while nobody can see the card, nothing
/// runs.
struct PlayerScrubber: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    let accentColor: Color

    @StateObject private var state = ScrubberState()
    /// Hidden while the notch is closed (see `notchCardActive`).
    @Environment(\.notchCardActive) private var cardActive

    private static let timeWidth: CGFloat = 38

    var body: some View {
        let schedule = PlaybackClockSchedule(
            track: media.currentTrack,
            isActive: media.currentTrack.isPlaying && power.isNotchVisible && cardActive
        )
        TimelineView(schedule) { clock in
            scrubber(at: clock.date)
        }
        // One adjustable control for VoiceOver, rather than two labels and
        // a bar it can't move: swipe up or down to skip ten seconds.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityPosition)
        .accessibilityAdjustableAction { direction in
            let track = media.currentTrack
            guard track.duration > 0 else { return }
            let step: Double = direction == .increment ? 10 : -10
            media.seek(to: (track.currentPosition + step) / track.duration)
        }
    }

    private var accessibilityPosition: String {
        let track = media.currentTrack
        return "\(TimeFormatting.clock(track.currentPosition)) of \(TimeFormatting.clock(track.duration))"
    }

    private var isActive: Bool {
        state.isHovered || state.isDragging
    }

    private func scrubber(at now: Date) -> some View {
        let track = media.currentTrack
        let position = state.isDragging
            ? state.dragRatio * track.duration
            : track.position(at: now)

        // Where the fill should be, and how to get there: during steady
        // playback it just steps along with each tick. A new song, a seek or
        // a re-sync springs there instead of jumping across the bar.
        let target = state.isDragging ? state.dragRatio : track.progressRatio(at: now)
        let step = (target - state.lastRatio) * track.duration
        let motion: Animation? = state.isDragging || (-0.25...1.5).contains(step)
            ? nil
            : .spring(response: 0.45, dampingFraction: 0.85)
        state.lastRatio = target

        let elapsed = position.rounded(.down)
        // Whole seconds on both sides, so the two always add up to the
        // track's length instead of the remaining side running a second short.
        let remaining = track.duration.rounded(.down) - elapsed

        return HStack(spacing: 10) {
            Text(TimeFormatting.clock(position))
                .rollingDigits(value: elapsed, countsDown: false)
                .frame(width: Self.timeWidth, alignment: .trailing)

            bar(ratio: target, motion: motion)

            Text("-\(TimeFormatting.clock(remaining))")
                .rollingDigits(value: remaining, countsDown: true)
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

/// See `NotchInteractionState` for why view state lives in an `ObservableObject`.
private final class ScrubberState: ObservableObject {
    @Published var isDragging = false
    @Published var dragRatio: Double = 0
    @Published var isHovered = false
    /// The fill's last target, to tell a steady step from a jump. Not
    /// published: it's bookkeeping, not something to redraw for.
    var lastRatio: Double = 0
}

private extension View {
    /// The digits that change roll into place, like the system's own Now
    /// Playing timer: up as time passes, down as the remaining time runs out.
    /// A short animation once a second, only while the card is open and
    /// playing; before macOS 14 the digits simply change.
    @ViewBuilder
    func rollingDigits(value: Double, countsDown: Bool) -> some View {
        if #available(macOS 14, *) {
            self
                .contentTransition(.numericText(countsDown: countsDown))
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: value)
        } else {
            self
        }
    }
}
