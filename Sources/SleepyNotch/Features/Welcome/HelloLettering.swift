import SwiftUI
import AppKit
import QuartzCore

/// A hand-written "hello" that writes itself, as one continuous pen line.
///
/// The writing is a Core Animation stroke (`strokeEnd` from 0 to 1), so the
/// window server draws it: the app does no work per frame, and nothing runs
/// once the word is complete.
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

    private let stroke = CAShapeLayer()
    private let delay: TimeInterval
    private var started = false

    init(delay: TimeInterval) {
        self.delay = delay
        super.init(frame: .zero)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.cgColor
        stroke.lineCap = .round
        stroke.lineJoin = .round
        // Hidden until the pen starts.
        stroke.strokeEnd = 0
        layer?.addSublayer(stroke)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        let fitted = HelloPath.fitted(in: bounds)
        stroke.path = fitted.path
        stroke.lineWidth = fitted.lineWidth
        stroke.contentsScale = window?.backingScaleFactor ?? 2
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
        stroke.strokeEnd = 1
        CATransaction.commit()

        // Reduce Motion: the word is simply there.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let write = CABasicAnimation(keyPath: "strokeEnd")
        write.fromValue = 0
        write.toValue = 1
        write.duration = Self.writeDuration
        write.beginTime = stroke.convertTime(CACurrentMediaTime(), from: nil) + delay
        // Before it starts, hold at nothing written.
        write.fillMode = .backwards
        // The pen eases in, keeps an even pace through the letters, and
        // lifts off gently at the end of the o.
        write.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.25, 1.0)
        stroke.add(write, forKey: "write")
    }
}

/// The word's single pen line. Drawn by hand in a 170 × 80 box (y down):
/// baseline at 70, x-height at 45, loops reaching 5. A slight forward slant
/// is applied after, as with real handwriting.
enum HelloPath {
    /// Pen width in the drawing's own units.
    private static let penWidth: CGFloat = 3.9
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
