import SwiftUI
import QuartzCore

/// The timeline: elapsed time, the progress bar, remaining time, on one row.
/// The played part is one clean colour that glides continuously with the
/// song. Reach for the bar and it swells softly; drag or click anywhere on
/// it to seek. A new song, a seek or a re-sync springs the fill to its new
/// spot instead of jumping.
///
/// Battery: the glide is a single Core Animation animation, from where the
/// song is to its end, handed to the window server and run there. The app
/// does nothing per frame. (Animated in SwiftUI, every frame also redrew the
/// title and times around it on the processor: about 5% CPU with the card
/// open.) The times change once a second, without an animation, for the
/// same reason. Paused, or while nobody can see the card, nothing runs.
struct PlayerScrubber: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    let accentColor: Color
    /// On the lock screen card, where the notch itself counts as hidden:
    /// the clock then runs whenever the screen is lit.
    var onLockScreen = false

    @StateObject private var state = ScrubberState()
    /// Hidden while the notch is closed (see `notchCardActive`).
    @Environment(\.notchCardActive) private var cardActive

    private static let timeWidth: CGFloat = 38

    private var isRunning: Bool {
        guard media.currentTrack.isPlaying else { return false }
        return onLockScreen ? power.isScreenOn : power.isNotchVisible && cardActive
    }

    var body: some View {
        let schedule = PlaybackClockSchedule(track: media.currentTrack, isActive: isRunning)
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

        let elapsed = position.rounded(.down)
        // Whole seconds on both sides, so the two always add up to the
        // track's length instead of the remaining side running a second short.
        let remaining = track.duration.rounded(.down) - elapsed

        return HStack(spacing: 10) {
            Text(TimeFormatting.clock(position))
                .frame(width: Self.timeWidth, alignment: .trailing)

            bar

            Text("-\(TimeFormatting.clock(remaining))")
                .frame(width: Self.timeWidth, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .medium))
        .monospacedDigit()
        .foregroundColor(isActive ? Theme.Text.secondary : Theme.Text.tertiary)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private var bar: some View {
        let thickness: CGFloat = isActive ? 8 : 5
        let track = media.currentTrack
        // Where the fill is now, and how fast it moves: the song's share of
        // the bar per second while it plays here, otherwise still.
        let ratio = state.isDragging ? state.dragRatio : track.progressRatio(at: Date())
        let rate = !state.isDragging && isRunning && track.duration > 0 ? 1 / track.duration : 0

        return GeometryReader { geo in
            let w = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.2 : 0.14))

                ProgressFill(
                    ratio: ratio,
                    rate: rate,
                    color: NSColor(accentColor.opacity(isActive ? 1 : 0.9)),
                    followsDrag: state.isDragging
                )
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isActive)
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
}

// MARK: - The fill

/// The played part of the bar, as one Core Animation layer.
private struct ProgressFill: NSViewRepresentable {
    let ratio: Double
    /// Share of the bar gained per second; 0 holds still.
    let rate: Double
    let color: NSColor
    /// Under the finger: follow it exactly, with no motion.
    let followsDrag: Bool

    func makeNSView(context: Context) -> ProgressFillView {
        ProgressFillView()
    }

    func updateNSView(_ view: ProgressFillView, context: Context) {
        view.update(ratio: ratio, rate: rate, color: color, followsDrag: followsDrag)
    }
}

final class ProgressFillView: NSView {
    private let fill = CALayer()
    private var ratio: Double = 0
    private var rate: Double = 0
    private var followsDrag = false
    /// What the fill was last set up for, to leave a running glide alone
    /// when an update changes nothing.
    private var configured: (rate: Double, size: CGSize)?

    private static let glideKey = "glide"
    private static let jumpKey = "jump"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.cornerCurve = .circular
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(ratio: Double, rate: Double, color: NSColor, followsDrag: Bool) {
        self.ratio = min(max(ratio, 0), 1)
        self.rate = rate
        self.followsDrag = followsDrag
        let cgColor = color.cgColor
        if fill.backgroundColor != cgColor {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.backgroundColor = cgColor
            CATransaction.commit()
        }
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    private func width(for ratio: Double) -> CGFloat {
        let h = bounds.height
        return max(h, bounds.width * CGFloat(ratio))
    }

    private func apply() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // The height follows the hover swell every frame; that never
        // disturbs the glide, which only animates the width.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.position = CGPoint(x: 0, y: size.height / 2)
        fill.bounds.size.height = size.height
        fill.cornerRadius = size.height / 2
        CATransaction.commit()

        let start = width(for: ratio)
        let shown = fill.presentation()?.bounds.width ?? fill.bounds.width

        // Already gliding to the right place at the right speed: leave it.
        // (Every tick of the clock lands here; restarting the animation each
        // time would make it stutter.)
        if !followsDrag, let configured, configured.rate == rate, configured.size.width == size.width,
           abs(shown - start) < 1 {
            return
        }
        let firstTime = configured == nil
        configured = (rate, size)

        fill.removeAnimation(forKey: Self.glideKey)
        fill.removeAnimation(forKey: Self.jumpKey)

        let end = rate > 0 ? width(for: 1) : start
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds.size.width = end
        CATransaction.commit()

        if rate > 0 {
            let glide = CABasicAnimation(keyPath: "bounds.size.width")
            glide.fromValue = start
            glide.toValue = end
            glide.duration = max(0.01, (1 - ratio) / rate)
            glide.timingFunction = CAMediaTimingFunction(name: .linear)
            // About a point a second on a typical song: a few frames a
            // second is all it takes to look continuous.
            glide.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 30, preferred: 15)
            fill.add(glide, forKey: Self.glideKey)
        }

        // A new song, a seek or a re-sync: spring from where it was.
        if !firstTime, !followsDrag, abs(shown - start) >= 1 {
            let jump = CASpringAnimation(keyPath: "bounds.size.width")
            jump.fromValue = shown - start
            jump.toValue = 0
            jump.isAdditive = true
            jump.mass = 1
            jump.stiffness = 158 // a 0.5 s response
            jump.damping = 20.6 // 0.82 damping fraction
            jump.duration = jump.settlingDuration
            fill.add(jump, forKey: Self.jumpKey)
        }
    }
}
