import SwiftUI

/// Which side of the notch a bubble sits on.
enum NotchSide {
    case leading
    case trailing

    /// -1 to the left, +1 to the right.
    var sign: CGFloat { self == .trailing ? 1 : -1 }
}

/// A small black bubble beside the closed notch, like the Dynamic Island's
/// second activity: the notch keeps the song, and the charge or the
/// microphone gets a bubble of its own.
///
/// It's drawn as part of the notch's own path (see `NotchShape`), so it's
/// cut by the same mask and moves on the same spring. Splitting off, it
/// slides out of the notch's side while a neck stretches between the two,
/// thins and lets go, like a drop of liquid; going back, the neck reaches
/// out again and the bubble melts into the notch.
struct NotchBubble: Equatable {
    /// 0: tucked inside the notch. 1: split off, resting beside it. The
    /// spring carries it a little past 1 and back, which reads as a bounce.
    var progress: CGFloat
    /// Full size. A circle when the width equals the height, a capsule when
    /// it's wider.
    var width: CGFloat
    var height: CGFloat
    /// The centre's distance below the top of the notch.
    var centerY: CGFloat

    static let hidden = NotchBubble(progress: 0, width: 0, height: 0, centerY: 0)

    /// Space between the notch and a resting bubble.
    static let gap: CGFloat = 6
    /// How far apart the neck lets go.
    private static let breakDistance: CGFloat = 4.5
    /// Tucked away, the bubble sits this far inside the notch's edge.
    private static let tuck: CGFloat = 3
    /// The bubble's size while tucked away, as a fraction of its full size:
    /// it grows as it comes out.
    private static let minScale: CGFloat = 0.5

    typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>

    var animatableData: AnimatableData {
        get { AnimatablePair(progress, width) }
        set {
            progress = newValue.first
            width = newValue.second
        }
    }

    var isShown: Bool { progress > 0.5 }

    /// Where a bubble measures its gap from: the body's side, pushed out
    /// past any top flare wider than the closed notch's, so a bubble beside
    /// an open notch keeps clear of its flare too.
    static func anchor(bodyEdge: CGFloat, flare: CGFloat, side: NotchSide) -> CGFloat {
        bodyEdge + side.sign * max(0, flare - NotchMetrics.wingsTopFlare)
    }

    /// How big the bubble is drawn right now. Linear in `progress`, so
    /// SwiftUI content scaled the same way stays in step with the path.
    var scale: CGFloat {
        Self.minScale + (1 - Self.minScale) * max(0, progress)
    }

    /// The centre's x for a notch body whose side is at `bodyEdge`. Also
    /// linear in `progress`, for the same reason.
    func centerX(side: NotchSide, bodyEdge: CGFloat) -> CGFloat {
        let tucked = bodyEdge - side.sign * (width / 2 + Self.tuck)
        let resting = bodyEdge + side.sign * (Self.gap + width / 2)
        return tucked + (resting - tucked) * progress
    }

    func frame(side: NotchSide, bodyEdge: CGFloat, top: CGFloat) -> CGRect {
        let w = max(width, height) * scale
        let h = height * scale
        let cx = centerX(side: side, bodyEdge: bodyEdge)
        return CGRect(x: cx - w / 2, y: top + centerY - h / 2, width: w, height: h)
    }

    /// Adds the bubble, and the neck while it's still joined, to the
    /// notch's path. Every piece winds the same way as the notch, so the
    /// overlaps fill as one shape.
    func add(to path: inout Path, side: NotchSide, bodyEdge: CGFloat, top: CGFloat) {
        guard progress > 0.002, width > 0, height > 0 else { return }
        let rect = frame(side: side, bodyEdge: bodyEdge, top: top)
        Self.addCapsule(rect, to: &path)
        addNeck(to: &path, side: side, bodyEdge: bodyEdge, bubble: rect)
    }

    /// The neck between the notch's side and the bubble: full while the
    /// bubble is still pressed into the notch, pinching in the middle as it
    /// pulls away, gone at `breakDistance`.
    private func addNeck(to path: inout Path, side: NotchSide, bodyEdge: CGFloat, bubble: CGRect) {
        let radius = bubble.height / 2
        let cy = bubble.midY
        // How far the bubble's near side is from the notch.
        let distance = side == .trailing ? bubble.minX - bodyEdge : bodyEdge - bubble.maxX
        let stretch = min(1, max(0, distance / Self.breakDistance))
        // Half-heights where the neck meets the notch and the bubble, and
        // at its waist.
        let notchHalf = radius * 0.82
        let bubbleHalf = radius * 0.72
        let waist = bubbleHalf * 0.8 * pow(1 - stretch, 1.6)
        guard waist > 0.5 else { return }
        // Attach just inside each shape, so the joins never show a seam.
        // On a circle, a chord at 0.72 of the radius sits 0.31 of the radius
        // in from its side.
        let notchX = bodyEdge - side.sign * 3
        let bubbleX = side == .trailing
            ? bubble.minX + radius * 0.31 + 0.8
            : bubble.maxX - radius * 0.31 - 0.8
        guard (bubbleX - notchX) * side.sign > 2 else { return }
        // Both control points at the middle: the curve's midpoint then sits
        // at (a + b)/8 + ¾ c from the centre line, solved here for `waist`.
        let control = (waist - (notchHalf + bubbleHalf) / 8) / 0.75
        let midX = (notchX + bubbleX) / 2

        // Left to right along the top, as the notch is drawn.
        let (leftX, leftHalf, rightX, rightHalf) = side == .trailing
            ? (notchX, notchHalf, bubbleX, bubbleHalf)
            : (bubbleX, bubbleHalf, notchX, notchHalf)
        path.move(to: CGPoint(x: leftX, y: cy - leftHalf))
        path.addCurve(
            to: CGPoint(x: rightX, y: cy - rightHalf),
            control1: CGPoint(x: midX, y: cy - control),
            control2: CGPoint(x: midX, y: cy - control)
        )
        path.addLine(to: CGPoint(x: rightX, y: cy + rightHalf))
        path.addCurve(
            to: CGPoint(x: leftX, y: cy + leftHalf),
            control1: CGPoint(x: midX, y: cy + control),
            control2: CGPoint(x: midX, y: cy + control)
        )
        path.closeSubpath()
    }

    /// A capsule wound like the notch (along the top left to right), from
    /// four quarter-circle cubics.
    private static func addCapsule(_ rect: CGRect, to path: inout Path) {
        let r = rect.height / 2
        let k = r * 0.5523
        let left = rect.minX + r
        let right = rect.maxX - r
        let midY = rect.midY
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: right + k, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: midY - k)
        )
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: midY + k),
            control2: CGPoint(x: right + k, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: midY),
            control1: CGPoint(x: left - k, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: midY + k)
        )
        path.addCurve(
            to: CGPoint(x: left, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: midY - k),
            control2: CGPoint(x: left - k, y: rect.minY)
        )
        path.closeSubpath()
    }
}
