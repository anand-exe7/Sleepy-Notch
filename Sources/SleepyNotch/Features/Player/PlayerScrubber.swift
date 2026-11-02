import SwiftUI

/// The timeline: elapsed time, the progress bar, remaining time, on one row.
/// The played part brightens toward the playhead, and while a song plays a
/// soft sheen sweeps along it. Reach for the bar and it thickens and shows a
/// playhead knob; drag or click anywhere on it to seek.
///
/// The sheen redraws at 30 frames a second, only while the card is open and
/// the song is playing, and only the sheen itself — not the bar or times.
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
        let thickness: CGFloat = isActive ? 9 : 5
        let live = media.currentTrack.isPlaying
            && !media.currentTrack.isPlaceholder
            && cardActive
            && power.isNotchVisible
            && power.allowsDecorativeMotion
            && !isActive

        return GeometryReader { geo in
            let w = geo.size.width
            let fill = max(thickness, w * min(max(ratio, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.2 : 0.14))
                    .frame(height: thickness)

                PlayedFill(thickness: thickness, color: accentColor, live: live)
                    .frame(width: fill)

                // The playhead, only while you're reaching for the bar.
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: 13, height: 13)
                    .scaleEffect(isActive ? 1 : 0.2)
                    .opacity(isActive ? 1 : 0)
                    .offset(x: fill - 6.5)
            }
            .animation(motion, value: ratio)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isActive)
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

/// The played part of the bar: the accent, brightening toward the
/// playhead, with a soft band of light sweeping along it while the song
/// plays.
private struct PlayedFill: View {
    let thickness: CGFloat
    let color: Color
    let live: Bool

    /// The sheen's width and speed, in points and points per second.
    private static let band: CGFloat = 54
    private static let speed: Double = 64
    /// A rest between sweeps, as a distance travelled off the end.
    private static let rest: CGFloat = 90

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [color.opacity(0.5), color],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .overlay(alignment: .leading) {
                if live {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                        GeometryReader { geo in
                            let travel = geo.size.width + Self.band + Self.rest
                            let distance = CGFloat((timeline.date.timeIntervalSinceReferenceDate * Self.speed)
                                .truncatingRemainder(dividingBy: Double(travel)))
                            LinearGradient(
                                colors: [.white.opacity(0), .white.opacity(0.6), .white.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: Self.band)
                            .offset(x: distance - Self.band)
                        }
                    }
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                }
            }
            .clipShape(Capsule())
            .frame(height: thickness)
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
