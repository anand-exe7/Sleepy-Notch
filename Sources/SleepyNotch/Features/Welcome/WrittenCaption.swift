import SwiftUI
import AppKit
import QuartzCore

/// A line of text that writes itself in from left to right, behind a soft
/// edge, as if the pen carried on after the "hello". It rises a couple of
/// points as it comes in.
///
/// Core Animation, like `HelloLettering`: a text layer under a sliding
/// gradient mask, so the window server does the work and nothing runs once
/// the line is in.
struct WrittenCaption: NSViewRepresentable {
    let text: String
    /// Seconds after appearing before the line starts.
    var delay: TimeInterval
    var duration: TimeInterval = 0.9

    func makeNSView(context: Context) -> WrittenCaptionView {
        WrittenCaptionView(text: text, delay: delay, duration: duration)
    }

    func updateNSView(_ view: WrittenCaptionView, context: Context) {}
}

final class WrittenCaptionView: NSView {
    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let color = NSColor.white.withAlphaComponent(0.6)
    /// How soft the leading edge of the reveal is, in points.
    private static let edge: CGFloat = 36

    /// Holds the text and carries the mask (AppKit manages the view's own
    /// layer, so the mask isn't put there).
    private let container = CALayer()
    private let line = CATextLayer()
    /// Opaque behind the pen, clear ahead of it.
    private let wipe = CAGradientLayer()
    private let delay: TimeInterval
    private let duration: TimeInterval
    private var started = false

    init(text: String, delay: TimeInterval, duration: TimeInterval) {
        self.delay = delay
        self.duration = duration
        super.init(frame: .zero)
        wantsLayer = true

        line.string = NSAttributedString(string: text, attributes: [
            .font: Self.font,
            .foregroundColor: Self.color,
            .kern: 0.1,
        ])
        line.alignmentMode = .center
        line.truncationMode = .end

        wipe.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        wipe.startPoint = CGPoint(x: 0, y: 0.5)
        wipe.endPoint = CGPoint(x: 1, y: 0.5)

        container.addSublayer(line)
        container.mask = wipe
        layer?.addSublayer(container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        let font = Self.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let reach = bounds.width + Self.edge
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        line.contentsScale = window?.backingScaleFactor ?? 2
        line.frame = CGRect(x: 0, y: (bounds.height - lineHeight) / 2, width: bounds.width, height: lineHeight)
        // Parked just left of the text (nothing showing); sliding right by
        // its own width uncovers all of it. Placed by bounds and position,
        // not frame, since it carries a transform.
        wipe.bounds = CGRect(x: 0, y: 0, width: reach, height: bounds.height)
        wipe.position = CGPoint(x: -reach / 2, y: bounds.height / 2)
        wipe.locations = [0, NSNumber(value: Double(bounds.width / reach)), 1]
        CATransaction.commit()
        startIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startIfReady()
    }

    private func startIfReady() {
        guard !started, window != nil, bounds.width > 0 else { return }
        started = true
        let reach = bounds.width + Self.edge

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wipe.transform = CATransform3DMakeTranslation(reach, 0, 0)
        CATransaction.commit()

        // Reduce Motion: the line is simply there.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let reveal = CABasicAnimation(keyPath: "transform.translation.x")
        reveal.fromValue = 0
        reveal.toValue = reach
        reveal.duration = duration
        reveal.beginTime = wipe.convertTime(CACurrentMediaTime(), from: nil) + delay
        reveal.fillMode = .backwards
        reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.0, 0.25, 1.0)
        wipe.add(reveal, forKey: "reveal")

        // A gentle rise into place (layers here are y-up).
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -3
        rise.toValue = 0
        rise.duration = duration + 0.2
        rise.beginTime = line.convertTime(CACurrentMediaTime(), from: nil) + delay
        rise.fillMode = .backwards
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        line.add(rise, forKey: "rise")
    }
}
