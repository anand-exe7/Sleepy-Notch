import SwiftUI
import QuartzCore

/// Four bars that dance while a song plays, like the Dynamic Island's, and
/// settle into a row of dots when it's paused.
///
/// Decorative only: no audio is captured. Each bar loops through its own
/// smooth run of heights, on a different length of loop, so together they
/// read as music without needing microphone or system-audio access.
///
/// Battery: the dance is a Core Animation animation, handed to the window
/// server once and run there. This app does no work per frame. (Drawn in
/// SwiftUI, 20 times a second, the bars beside the closed notch were most of
/// the app's CPU while music played.) It runs only while a song plays and
/// motion is welcome (`animates`); otherwise the animation is removed.
struct EqualizerBars: View {
    let isPlaying: Bool
    /// False under Low Power Mode or Reduce Motion, or while the bars can't
    /// be seen: they hold still, raised while playing.
    let animates: Bool
    var color: Color = .white
    /// The highest rate the window server should draw the dance at. The bars
    /// are small, so beside the closed notch a lower rate looks the same.
    var framesPerSecond: Double = 30

    var body: some View {
        BarsLayerRepresentable(
            isPlaying: isPlaying,
            animates: animates,
            color: NSColor(color),
            framesPerSecond: Float(framesPerSecond)
        )
        .accessibilityHidden(true)
    }
}

private struct BarsLayerRepresentable: NSViewRepresentable {
    let isPlaying: Bool
    let animates: Bool
    let color: NSColor
    let framesPerSecond: Float

    func makeNSView(context: Context) -> BarsLayerView {
        BarsLayerView()
    }

    func updateNSView(_ view: BarsLayerView, context: Context) {
        view.update(isPlaying: isPlaying, animates: animates, color: color, framesPerSecond: framesPerSecond)
    }
}

final class BarsLayerView: NSView {
    private static let barCount = 4
    private static let barWidth: CGFloat = 3
    /// Per bar: its loop of levels (0…1, first and last equal so it loops
    /// without a seam) and how long one loop takes. The lengths don't divide
    /// into each other, so the four never fall into step.
    private static let loops: [(levels: [CGFloat], duration: CFTimeInterval)] = [
        ([0.42, 0.9, 0.55, 0.75, 0.32, 0.95, 0.6, 0.38, 0.82, 0.42], 2.3),
        ([0.75, 0.4, 1.0, 0.58, 0.85, 0.36, 0.7, 0.98, 0.5, 0.75], 2.9),
        ([0.55, 0.95, 0.4, 0.8, 0.62, 0.3, 0.88, 0.5, 0.7, 0.55], 2.6),
        ([0.35, 0.68, 0.92, 0.45, 0.6, 0.85, 0.32, 0.72, 0.5, 0.35], 3.3),
    ]
    /// Still heights for playing without motion: a gentle arch.
    private static let restingLevels: [CGFloat] = [0.45, 0.8, 0.65, 0.35]
    private static let danceKey = "dance"
    private static let riseKey = "rise"
    /// How long a bar takes to reach the start of its loop when it begins
    /// dancing from somewhere else (a dot, or mid-spring).
    private static let riseDuration: CFTimeInterval = 0.22

    private var bars: [CALayer] = []
    private var isPlaying = false
    private var animates = false
    private var framesPerSecond: Float = 30
    /// What the bars are currently set up for, so an update that changes
    /// nothing leaves the running animation alone.
    private var configured: (playing: Bool, dancing: Bool, height: CGFloat, fps: Float)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            bar.cornerCurve = .circular
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(isPlaying: Bool, animates: Bool, color: NSColor, framesPerSecond: Float) {
        self.isPlaying = isPlaying
        self.animates = animates
        self.framesPerSecond = framesPerSecond
        let cgColor = color.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars where bar.backgroundColor != cgColor {
            bar.backgroundColor = cgColor
        }
        CATransaction.commit()
        apply()
    }

    override func layout() {
        super.layout()
        let count = CGFloat(Self.barCount)
        let spacing = max(0, (bounds.width - Self.barWidth * count) / (count - 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(
                x: Self.barWidth / 2 + CGFloat(index) * (Self.barWidth + spacing),
                y: bounds.midY
            )
            bar.bounds.size.width = Self.barWidth
        }
        CATransaction.commit()
        apply()
    }

    /// Puts the bars in the right state: dancing, raised and still, or
    /// down as dots. Only touches them when that state actually changes.
    private func apply() {
        let height = bounds.height
        guard height > 0 else { return }
        let dancing = isPlaying && animates
        let state = (playing: isPlaying, dancing: dancing, height: height, fps: framesPerSecond)
        if let configured, configured == state { return }
        let wasConfigured = configured != nil
        configured = state

        for (index, bar) in bars.enumerated() {
            // Where the bar is on screen right now, mid-dance or mid-spring,
            // so the next motion starts from there instead of jumping.
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.removeAnimation(forKey: Self.danceKey)
            bar.removeAnimation(forKey: Self.riseKey)

            let target: CGFloat
            if dancing {
                target = Self.height(Self.loops[index].levels[0], in: height)
            } else if isPlaying {
                target = Self.height(Self.restingLevels[index], in: height)
            } else {
                target = Self.barWidth
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.bounds.size.height = target
            CATransaction.commit()

            if dancing {
                // Rise (or fall) to where the loop starts, then dance from
                // there, so nothing jumps.
                var start = CACurrentMediaTime()
                if wasConfigured, abs(current - target) > 0.5 {
                    let rise = CABasicAnimation(keyPath: "bounds.size.height")
                    rise.fromValue = current
                    rise.toValue = target
                    rise.duration = Self.riseDuration
                    rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bar.add(rise, forKey: Self.riseKey)
                    start += Self.riseDuration
                }
                bar.add(dance(for: index, height: height, startingAt: start), forKey: Self.danceKey)
            } else if wasConfigured, abs(current - target) > 0.5 {
                // Playing ↔ paused springs the bars up or down.
                let spring = CASpringAnimation(keyPath: "bounds.size.height")
                spring.fromValue = current
                spring.toValue = target
                spring.mass = 1
                spring.stiffness = 247 // a 0.4 s response
                spring.damping = 18.8 // 0.6 damping fraction
                spring.duration = spring.settlingDuration
                bar.add(spring, forKey: Self.danceKey)
            }
        }
    }

    /// One bar's endless loop, eased through its levels.
    private func dance(for index: Int, height: CGFloat, startingAt start: CFTimeInterval) -> CAAnimation {
        let loop = Self.loops[index]
        let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
        animation.values = loop.levels.map { Self.height($0, in: height) }
        animation.duration = loop.duration
        animation.calculationMode = .cubic
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = start
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(15, framesPerSecond),
            maximum: framesPerSecond,
            preferred: framesPerSecond
        )
        return animation
    }

    private static func height(_ level: CGFloat, in height: CGFloat) -> CGFloat {
        max(barWidth, height * level)
    }
}
