import SwiftUI
import QuartzCore

/// Bars that follow your voice while an app uses the mic: tall while you
/// speak, a row of dots when you're quiet.
///
/// The level comes from `MicLevelMonitor` about 15 times a second and goes
/// straight into Core Animation layers; each step is a short implicit
/// animation run by the window server, so SwiftUI never redraws for it.
/// Without the microphone permission (or while not listening) the dots
/// ripple slowly instead, once, and then rest as dots. With
/// `animates` off (Low Power Mode, notch hidden) they hold still.
struct MicWaveView: View {
    var barCount = 4
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var height: CGFloat = 13
    var color: Color = Theme.Status.warning
    let animates: Bool

    var body: some View {
        MicWaveRepresentable(
            barCount: barCount,
            barWidth: barWidth,
            spacing: spacing,
            color: NSColor(color),
            animates: animates
        )
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing, height: height)
        .accessibilityHidden(true)
    }
}

private struct MicWaveRepresentable: NSViewRepresentable {
    let barCount: Int
    let barWidth: CGFloat
    let spacing: CGFloat
    let color: NSColor
    let animates: Bool

    func makeNSView(context: Context) -> MicWaveLayerView {
        MicWaveLayerView(barCount: barCount, barWidth: barWidth, spacing: spacing)
    }

    func updateNSView(_ view: MicWaveLayerView, context: Context) {
        view.update(color: color, animates: animates)
    }

    static func dismantleNSView(_ view: MicWaveLayerView, coordinator: ()) {
        view.detach()
    }
}

final class MicWaveLayerView: NSView {
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private var bars: [CALayer] = []
    /// How much of the level each bar takes: tallest in the middle.
    private let weights: [CGFloat]
    private var animates = false
    private var isLive = false
    private var token: UUID?
    /// The heights last sent, so a level that changes nothing (silence)
    /// costs no frames at all.
    private var targets: [CGFloat] = []

    init(barCount: Int, barWidth: CGFloat, spacing: CGFloat) {
        self.barWidth = barWidth
        self.spacing = spacing
        weights = (0..<barCount).map { index in
            let middle = CGFloat(barCount - 1) / 2
            let distance = abs(CGFloat(index) - middle) / max(1, middle)
            return 1 - 0.45 * distance
        }
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    /// The one ripple has played for this stretch without a live level.
    private var hasRippled = false

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: NSColor, animates: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = color.cgColor }
        CATransaction.commit()
        guard animates != self.animates || token == nil else { return }
        self.animates = animates
        if animates {
            attach()
        } else {
            detach()
            showDots()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let x = CGFloat(index) * (barWidth + spacing)
            bar.position = CGPoint(x: x + barWidth / 2, y: bounds.midY)
            if bar.bounds.height == 0 {
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
            }
        }
        CATransaction.commit()
        // The ripple's height depends on the size, known only now.
        if animates && !isLive && !hasRippled && bounds.height > 0 {
            ripple()
        }
    }

    // MARK: - Level

    private func attach() {
        guard token == nil else { return }
        token = MicLevelMonitor.shared.addObserver(
            onLevel: { [weak self] level in self?.show(level: CGFloat(level)) },
            onLive: { [weak self] live in self?.setLive(live) }
        )
    }

    func detach() {
        if let token { MicLevelMonitor.shared.removeObserver(token) }
        token = nil
    }

    private func setLive(_ live: Bool) {
        isLive = live
        hasRippled = false
        if live {
            for bar in bars { bar.removeAnimation(forKey: "ripple") }
            show(level: 0)
        } else if animates {
            ripple()
        } else {
            showDots()
        }
    }

    /// Each step glides over a tenth of a second, drawn at no more than 30
    /// frames a second: an implicit animation would run at the display's
    /// full rate (120 on ProMotion), which cost the window server far more.
    private func show(level: CGFloat) {
        guard isLive, animates else { return }
        let maxHeight = bounds.height
        let next: [CGFloat] = bars.indices.map { index in
            // A little unevenness, so the bars read as a voice, not a meter.
            let jitter = level < 0.05 ? 1 : CGFloat.random(in: 0.7...1)
            let height = barWidth + (maxHeight - barWidth) * min(1, level * weights[index] * jitter * 1.3)
            return max(barWidth, height.rounded())
        }
        guard next != targets else { return }
        targets = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let from = bar.presentation()?.bounds ?? bar.bounds
            let to = CGRect(x: 0, y: 0, width: barWidth, height: next[index])
            bar.bounds = to
            let glide = CABasicAnimation(keyPath: "bounds")
            glide.fromValue = NSValue(rect: from)
            glide.toValue = NSValue(rect: to)
            glide.duration = 0.1
            glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            glide.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
            bar.add(glide, forKey: "glide")
        }
        CATransaction.commit()
    }

    private func showDots() {
        targets = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.removeAnimation(forKey: "ripple")
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
        }
        CATransaction.commit()
    }

    /// No live level: the dots swell one after another, once, and settle.
    /// No looping motion: that's handed to the window server and ends there.
    private func ripple() {
        showDots()
        // Sized only after layout, which starts it then.
        guard bounds.height > 0 else { return }
        hasRippled = true
        let tall = max(barWidth, bounds.height * 0.45)
        for (index, bar) in bars.enumerated() {
            let swell = CAKeyframeAnimation(keyPath: "bounds.size.height")
            swell.values = [barWidth, tall, barWidth, barWidth]
            swell.keyTimes = [0, 0.18, 0.38, 1]
            swell.duration = 1.8
            swell.beginTime = CACurrentMediaTime() + Double(index) * 0.14
            swell.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            swell.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
            bar.add(swell, forKey: "ripple")
        }
    }
}
