import SwiftUI
import QuartzCore

/// The countdown beside the notch when it's the main activity: the time,
/// counted down by the system from the end date.
struct TimerWingText: View {
    let session: TimerSession

    var body: some View {
        Text(timerInterval: session.start...session.end, countsDown: true, showsHours: false)
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundColor(Theme.Text.primary)
            .lineLimit(1)
            .accessibilityLabel("Timer")
    }
}

/// The timer as a bubble: a ring that runs down to the end. One Core
/// Animation animation from where it is now to empty, handed to the window
/// server: the app does no work while it runs.
struct TimerRing: NSViewRepresentable {
    let start: Date
    let end: Date

    func makeNSView(context: Context) -> TimerRingView {
        TimerRingView(start: start, end: end)
    }

    func updateNSView(_ view: TimerRingView, context: Context) {
        view.configure(start: start, end: end)
    }
}

final class TimerRingView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var start: Date
    private var end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
        super.init(frame: .zero)
        wantsLayer = true
        for layer in [track, arc] {
            layer.fillColor = nil
            layer.lineWidth = 2.4
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        arc.strokeColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(start: Date, end: Date) {
        guard start != self.start || end != self.end else { return }
        self.start = start
        self.end = end
        restart()
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height) - track.lineWidth
        guard side > 0 else { return }
        let rect = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        // From the top, clockwise, so the ring empties the way a clock runs.
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: side / 2,
            startAngle: -.pi / 2,
            endAngle: 1.5 * .pi,
            clockwise: false
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [track, arc] {
            layer.frame = bounds
            layer.path = path
        }
        CATransaction.commit()
        restart()
    }

    private func restart() {
        guard bounds.width > 0 else { return }
        let total = end.timeIntervalSince(start)
        let remaining = max(0, end.timeIntervalSinceNow)
        let fraction = total > 0 ? min(1, remaining / total) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.removeAllAnimations()
        arc.strokeEnd = 0
        CATransaction.commit()
        guard remaining > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            // Reduce Motion: the ring stays where it is, without running down.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.strokeEnd = CGFloat(fraction)
            CATransaction.commit()
            return
        }
        let run = CABasicAnimation(keyPath: "strokeEnd")
        run.fromValue = fraction
        run.toValue = 0
        run.duration = remaining
        run.timingFunction = CAMediaTimingFunction(name: .linear)
        run.fillMode = .forwards
        run.isRemovedOnCompletion = false
        run.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 10, preferred: 5)
        arc.add(run, forKey: "run")
    }
}

/// The opened timer: the time left, big, and a way to cancel it.
struct TimerDetail: View {
    let session: TimerSession?
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let session {
                    Text(timerInterval: session.start...session.end, countsDown: true, showsHours: false)
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.primary)
                }
                Text("Timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
            Spacer(minLength: 8)
            Button(action: cancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}

/// The timer ran out: a short row under the notch.
struct TimerDonePeekView: View {
    let minutes: Int

    static let contentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text(minutes <= 0 ? "Timer done" : minutes == 1 ? "1 minute timer done" : "\(minutes) minute timer done")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer done")
    }
}
