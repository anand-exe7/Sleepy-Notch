import SwiftUI
import AppKit
import QuartzCore

/// A hand-written "hello" that writes itself, as one continuous pen line
/// of thick, see-through, frosted white, like the greeting on a new Mac.
///
/// The pen line is a Core Animation stroke (`strokeEnd` from 0 to 1). Two
/// layers share its path and its writing animation: a translucent white
/// body, and a softer, brighter core down its middle that gives it
/// roundness. The window server draws all of it: the app does no work per
/// frame, and nothing runs once it has settled.
struct HelloLettering: NSViewRepresentable {
    /// Seconds after appearing before the pen starts, so the notch has
    /// mostly opened by then.
    var delay: TimeInterval = 0.3
    /// Apple's rainbow along the line (green, yellow, orange, red, purple,
    /// blue) instead of frosted white.
    var colourful = true

    func makeNSView(context: Context) -> HelloLetteringView {
        HelloLetteringView(delay: delay, colourful: colourful)
    }

    func updateNSView(_ view: HelloLetteringView, context: Context) {}
}

final class HelloLetteringView: NSView {
    /// How long the pen takes to write the word.
    static let writeDuration: CFTimeInterval = 2.1

    /// The glass: a see-through body, and a softer, brighter core inside it,
    /// on the same path.
    private let body = CAShapeLayer()
    private let core = CAShapeLayer()
    /// Colourful: the rainbow, shown only where the pen has written (its
    /// mask is the same stroke, written with the same animation).
    private let rainbow = CAGradientLayer()
    private let rainbowMask = CAShapeLayer()
    private let colourful: Bool
    private var layers: [CAShapeLayer] { colourful ? [rainbowMask] : [body, core] }
    private let delay: TimeInterval
    private var started = false

    /// The colours of Apple's own "hello", left to right.
    private static let appleColours: [NSColor] = [
        NSColor(srgbRed: 0.39, green: 0.77, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 0.98, green: 0.76, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.55, blue: 0.12, alpha: 1),
        NSColor(srgbRed: 0.89, green: 0.23, blue: 0.23, alpha: 1),
        NSColor(srgbRed: 0.59, green: 0.24, blue: 0.59, alpha: 1),
        NSColor(srgbRed: 0.01, green: 0.61, blue: 0.86, alpha: 1),
    ]

    init(delay: TimeInterval, colourful: Bool) {
        self.delay = delay
        self.colourful = colourful
        super.init(frame: .zero)
        wantsLayer = true
        if colourful {
            rainbow.colors = Self.appleColours.map(\.cgColor)
            rainbow.startPoint = CGPoint(x: 0, y: 0.5)
            rainbow.endPoint = CGPoint(x: 1, y: 0.5)
            rainbow.mask = rainbowMask
            self.layer?.addSublayer(rainbow)
        }
        for layer in layers where layer !== rainbowMask {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            // Hidden until the pen starts.
            layer.strokeEnd = 0
            self.layer?.addSublayer(layer)
        }
        rainbowMask.fillColor = nil
        rainbowMask.lineCap = .round
        rainbowMask.lineJoin = .round
        rainbowMask.strokeColor = NSColor.black.cgColor
        rainbowMask.strokeEnd = 0
        body.strokeColor = NSColor.white.withAlphaComponent(0.48).cgColor
        // The core feathers into the body rather than ending in a hard line.
        // (The colourful line is solid colour, as Apple's is: no gloss.)
        core.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor
        core.shadowColor = NSColor.white.cgColor
        core.shadowOpacity = 0.6
        core.shadowRadius = 2
        core.shadowOffset = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fitted = HelloPath.fitted(in: bounds)
        for layer in layers {
            layer.path = fitted.path
            layer.contentsScale = window?.backingScaleFactor ?? 2
            if layer !== rainbowMask { layer.frame = bounds }
        }
        // The colours span the word itself, so all six show: green at the
        // start of the h, blue at the end of the o.
        let box = fitted.path.boundingBoxOfPath.insetBy(dx: -fitted.lineWidth / 2, dy: -fitted.lineWidth / 2)
        rainbow.frame = box
        rainbowMask.frame = CGRect(x: -box.minX, y: -box.minY, width: bounds.width, height: bounds.height)
        rainbowMask.lineWidth = fitted.lineWidth
        body.lineWidth = fitted.lineWidth
        core.lineWidth = fitted.lineWidth * 0.4
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers { layer.strokeEnd = 1 }
        CATransaction.commit()

        // Reduce Motion: the word is simply there.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let write = CABasicAnimation(keyPath: "strokeEnd")
        write.fromValue = 0
        write.toValue = 1
        write.duration = Self.writeDuration
        write.beginTime = layers[0].convertTime(CACurrentMediaTime(), from: nil) + delay
        // Before it starts, hold at nothing written.
        write.fillMode = .backwards
        // The pen eases in, keeps an even pace through the letters, and
        // lifts off gently at the end of the o.
        write.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.25, 1.0)
        for layer in layers { layer.add(write, forKey: "write") }
    }
}

/// The word's single pen line. Drawn by hand in a 170 × 80 box (y down):
/// baseline at 70, x-height at 44, loops reaching 6. Open, rounded loops
/// and a thin even pen, like Apple's own "hello". A slight forward slant
/// is applied after, as with real handwriting.
enum HelloPath {
    /// Pen width in the drawing's own units.
    private static let penWidth: CGFloat = 4.8
    private static let slant: CGFloat = 0.12
    private static let baseline: CGFloat = 70

    /// Start point, then one cubic segment per row: control 1, control 2, end.
    private static let start = CGPoint(x: 2, y: 66)
    private static let segments: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        // h: lead-in, the tall loop, down the stem
        (12, 64, 27, 50, 34, 32),
        (39, 19, 42, 7, 36, 6),
        (29, 5, 25, 15, 24, 29),
        (23, 44, 22, 58, 21, 70),
        // …and its shoulder
        (24, 56, 32, 44, 41, 44),
        (49, 44, 51, 50, 50, 57),
        (49, 64, 50, 70, 57, 69),
        // e
        (64, 68, 72, 62, 75, 55),
        (77, 49, 74, 44, 69, 44),
        (62, 44, 58, 51, 59, 58),
        (60, 66, 67, 70, 76, 69),
        // l
        (85, 67, 94, 52, 98, 36),
        (101, 22, 101, 7, 95, 7),
        (89, 7, 87, 20, 87, 36),
        (87, 54, 89, 69, 97, 69),
        // l
        (105, 69, 113, 56, 117, 38),
        (120, 22, 120, 7, 114, 7),
        (108, 7, 106, 20, 106, 36),
        (106, 54, 108, 69, 117, 69),
        // o, and the little stroke off its top
        (125, 68, 131, 46, 143, 44),
        (135, 44, 130, 52, 131, 59),
        (132, 67, 138, 71, 144, 70),
        (151, 69, 156, 62, 155, 55),
        (154, 48, 149, 44, 143, 44),
        (149, 45, 157, 48, 167, 44),
    ]

    /// The word in drawing units, slanted, y down.
    private static let drawing: CGPath = {
        let path = CGMutablePath()
        path.move(to: start)
        for s in segments {
            path.addCurve(
                to: CGPoint(x: s.4, y: s.5),
                control1: CGPoint(x: s.0, y: s.1),
                control2: CGPoint(x: s.2, y: s.3)
            )
        }
        // Lean forward about the baseline.
        var lean = CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: slant * baseline, ty: 0)
        return path.copy(using: &lean) ?? path
    }()

    /// The word scaled to fit `rect` and centred in it, in a layer's
    /// y-up coordinates, with the pen width to match.
    static func fitted(in rect: CGRect) -> (path: CGPath, lineWidth: CGFloat) {
        let box = drawing.boundingBoxOfPath.insetBy(dx: -penWidth / 2, dy: -penWidth / 2)
        guard box.width > 0, box.height > 0, rect.width > 0, rect.height > 0 else {
            return (CGMutablePath(), 0)
        }
        let scale = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        return (drawing.copy(using: &transform) ?? drawing, penWidth * scale)
    }
}
