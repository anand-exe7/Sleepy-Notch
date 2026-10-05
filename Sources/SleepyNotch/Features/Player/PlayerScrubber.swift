import SwiftUI

/// Progress bar plus elapsed / remaining time. Thin until you reach for it:
/// hovering thickens the bar and shows the thumb, like the system's own
/// scrubbers. Drag or click anywhere on it to seek.
///
/// The only part of the card that changes on its own: it ticks once a second
/// while the track plays and the notch is visible (see
/// `PlaybackClockSchedule`), and nothing else redraws for it.
struct PlayerScrubber: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    let accentColor: Color

    @StateObject private var state = ScrubberState()

    var body: some View {
        TimelineView(PlaybackClockSchedule(
            track: media.currentTrack,
            isActive: media.currentTrack.isPlaying && power.isNotchVisible
        )) { clock in
            scrubber(at: clock.date)
        }
    }

    private var isActive: Bool {
        state.isHovered || state.isDragging
    }

    private func scrubber(at now: Date) -> some View {
        let barHeight: CGFloat = isActive ? 6 : 4
        let thumbSize: CGFloat = state.isDragging ? 12 : 10

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let ratio = state.isDragging ? state.dragRatio : media.currentTrack.progressRatio(at: now)
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: barHeight)

                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(barHeight, min(w * ratio, w)), height: barHeight)

                    // Centred on the playhead and clamped so it never
                    // overhangs either end.
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .opacity(isActive ? 1 : 0)
                        .offset(x: max(0, min(w * ratio - thumbSize / 2, w - thumbSize)))
                }
                .frame(height: geo.size.height)
                .animation(.easeOut(duration: 0.15), value: isActive)
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
            // A thin bar is hard to hit, so the drag target extends into the
            // space around it without changing the layout.
            .frame(height: 12)
            .contentShape(Rectangle().inset(by: -6))
            .onHover { state.isHovered = $0 }

            HStack {
                let position = state.isDragging
                    ? state.dragRatio * media.currentTrack.duration
                    : media.currentTrack.position(at: now)
                Text(TimeFormatting.clock(position))
                Spacer()
                Text("-\(TimeFormatting.clock(media.currentTrack.duration - position))")
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundColor(Theme.Text.tertiary)
        }
    }
}

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class ScrubberState: ObservableObject {
    @Published var isDragging = false
    @Published var dragRatio: Double = 0
    @Published var isHovered = false
}
