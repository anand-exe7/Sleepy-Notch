import SwiftUI
import AppKit
import QuartzCore

/// A hand-written "hello" that writes itself, as one continuous pen line
/// of thick, see-through, glossy white, like the greeting on a new Mac.
///
/// The pen line is a Core Animation stroke (`strokeEnd` from 0 to 1). Three
/// layers share its path and its writing animation: a translucent white
/// body, a faint shade along its bottom-right edge and a bright gloss along
/// its top-left. The window server draws all of it: the app does no work per
/// frame, and nothing runs once it has settled.
struct HelloLettering: NSViewRepresentable {
    /// Seconds after appearing before the pen starts, so the notch has
    /// mostly opened by then.
    var delay: TimeInterval = 0.3

    func makeNSView(context: Context) -> HelloLetteringView {
        HelloLetteringView(delay: delay)
    }

    func updateNSView(_ view: HelloLetteringView, context: Context) {}
}

final class HelloLetteringView: NSView {
    /// How long the pen takes to write the word.
    static let writeDuration: CFTimeInterval = 2.1

    /// The glass: a see-through body, with a faint shade below-right of it
    /// and a bright gloss above-left, all on the same path.
    private let body = CAShapeLayer()
    private let shade = CAShapeLayer()
    private let gloss = CAShapeLayer()
    private var layers: [CAShapeLayer] { [body, shade, gloss] }
    private let delay: TimeInterval
    private var started = false

    init(delay: TimeInterval) {
        self.delay = delay
        super.init(frame: .zero)
        wantsLayer = true
        for layer in layers {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            // Hidden until the pen starts.
            layer.strokeEnd = 0
            self.layer?.addSublayer(layer)
        }
        body.strokeColor = NSColor.white.withAlphaComponent(0.68).cgColor
        shade.strokeColor = NSColor.black.withAlphaComponent(0.14).cgColor
        gloss.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fitted = HelloPath.fitted(in: bounds)
        // The body is the full pen. The shade and gloss are thin lines
        // nudged to either side of it (layers are y-up: up-left is -x, +y),
        // so each sits along that edge of the body.
        let edgeWidth = max(0.8, fitted.lineWidth * 0.2)
        let nudge = (fitted.lineWidth - edgeWidth) / 2 / 2.0.squareRoot() * 0.8
        for layer in layers {
            layer.path = fitted.path
            layer.contentsScale = window?.backingScaleFactor ?? 2
        }
        body.lineWidth = fitted.lineWidth
        shade.lineWidth = edgeWidth * 1.4
        gloss.lineWidth = edgeWidth
        body.frame = bounds
        shade.frame = bounds.offsetBy(dx: nudge, dy: -nudge)
        gloss.frame = bounds.offsetBy(dx: -nudge, dy: nudge)
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
        write.beginTime = body.convertTime(CACurrentMediaTime(), from: nil) + delay
        // Before it starts, hold at nothing written.
        write.fillMode = .backwards
        // The pen eases in, keeps an even pace through the letters, and
        // lifts off gently at the end of the o.
        write.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.25, 1.0)
        for layer in layers { layer.add(write, forKey: "write") }
    }
}

/// The word's single pen line. Drawn by hand in a 170 × 80 box (y down):
/// baseline at 70, x-height at 45, loops reaching 5. A slight forward slant
/// is applied after, as with real handwriting.
enum HelloPath {
    /// Pen width in the drawing's own units.
    private static let penWidth: CGFloat = 6.4
    private static let slant: CGFloat = 0.16
    private static let baseline: CGFloat = 70

    /// Start point, then one cubic segment per row: control 1, control 2, end.
    private static let start = CGPoint(x: 4, y: 62)
    private static let segments: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        // h: lead-in, the tall loop, down the stem
        (13, 59, 25, 42, 31, 26),
        (36, 13, 35, 4, 30, 5),
        (24, 6, 21, 24, 20, 40),
        (19, 52, 18, 62, 17, 70),
        // …and its shoulder
        (20, 58, 27, 45, 36, 45),
        (44, 45, 44, 53, 43, 59),
        (42, 65, 44, 70, 50, 69),
        // e
        (57, 68, 64, 62, 68, 56),
        (71, 50, 69, 43, 63, 44),
        (56, 45, 53, 53, 54, 60),
        (55, 67, 61, 70, 69, 69),
        // l
        (77, 67, 87, 48, 91, 30),
        (94, 16, 93, 6, 88, 7),
        (83, 8, 81, 22, 81, 38),
        (81, 52, 81, 64, 85, 68),
        (88, 71, 94, 69, 98, 65),
        // l
        (105, 56, 113, 44, 116, 30),
        (119, 16, 118, 6, 113, 7),
        (108, 8, 106, 22, 106, 38),
        (106, 52, 106, 64, 110, 68),
        (113, 71, 119, 70, 123, 66),
        // o, and the little stroke off its top
        (127, 60, 133, 46, 142, 45),
        (134, 45, 129, 54, 130, 61),
        (131, 68, 137, 71, 143, 70),
        (150, 69, 153, 62, 152, 55),
        (151, 48, 147, 44, 142, 45),
        (148, 46, 155, 46, 163, 42),
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
