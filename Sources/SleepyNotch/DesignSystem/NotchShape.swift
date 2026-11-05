import SwiftUI

// Mirrors the physical MacBook notch, and grows out of it:
// - the top edge sits flush with the screen top
// - open, the top corners flare outward in a concave curve right at the
//   screen edge, so the card pours out of the top of the screen instead of
//   meeting it at a right angle. Below the flares the sides run straight:
//   nothing is wider than the card except that small curve
// - rounded bottom corners
//
// The bottom corners are Apple's continuous curve, like the MacBook's own
// screen and notch corners: they ease into the straight edges instead of
// meeting them with a jump in curvature, which reads as a kink next to the
// hardware.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    /// Radius of the outward flare at each top corner. The flares sit inside
    /// the shape's rect, so the body is `2 * topFlare` narrower than it. Zero
    /// while collapsed, so the closed notch matches the hardware cutout.
    var topFlare: CGFloat = 0
    /// The hardware notch is cut into the top edge, so its top corners meet
    /// the screen edge. The floating-pill fallback has no screen edge to blend
    /// into, so all four corners are rounded and `topFlare` is ignored.
    var roundsTopCorners: Bool = false
    var insetAmount: CGFloat = 0
    /// Small bubbles that split off the closed notch's sides, like the
    /// Dynamic Island's second activity (see `NotchBubble`).
    var leadingBubble = NotchBubble.hidden
    var trailingBubble = NotchBubble.hidden

    /// The flares run this many times further down the side than they reach
    /// out, like Droppy's: a long, soft sweep into the screen edge rather
    /// than a round bump.
    private static let flareAspect: CGFloat = 1.75
    /// Control-point offsets for the flare: longer than a circle's, so the
    /// curve leaves the screen edge and meets the side with no visible kink.
    private static let flareOut: CGFloat = 0.66
    private static let flareDown: CGFloat = 0.6

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<NotchBubble.AnimatableData, NotchBubble.AnimatableData>> {
        get {
            AnimatablePair(
                AnimatablePair(bottomRadius, topFlare),
                AnimatablePair(leadingBubble.animatableData, trailingBubble.animatableData)
            )
        }
        set {
            bottomRadius = newValue.first.first
            topFlare = newValue.first.second
            leadingBubble.animatableData = newValue.second.first
            trailingBubble.animatableData = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        var path = roundsTopCorners ? pill(in: rect) : flared(in: rect)
        // The body runs between the flares; bubbles split off its sides.
        let f = roundsTopCorners ? 0 : max(0, min(topFlare, rect.width / 4, rect.height / 2))
        trailingBubble.add(to: &path, side: .trailing, bodyEdge: NotchBubble.anchor(bodyEdge: rect.maxX - f, flare: f, side: .trailing), top: rect.minY)
        leadingBubble.add(to: &path, side: .leading, bodyEdge: NotchBubble.anchor(bodyEdge: rect.minX + f, flare: f, side: .leading), top: rect.minY)
        return path
    }

    /// Flat top flush with the screen, concave flares, rounded bottom.
    private func flared(in rect: CGRect) -> Path {
        let f = max(0, min(topFlare, rect.width / 4, rect.height / 2))
        // How far down the side the flare runs.
        let fy = min(f * Self.flareAspect, rect.height / 2)
        let top = rect.minY
        let left = rect.minX + f
        let right = rect.maxX - f
        // A continuous corner reaches (1 + smoothing) × its radius along each
        // edge, so the radius is limited by the room on the side and bottom.
        let reach = 1 + Self.cornerSmoothing
        let r = max(0, min(bottomRadius, (right - left) / 2 / reach, (rect.maxY - top - fy) / reach))
        let ox = f * Self.flareOut
        let oy = fy * Self.flareDown

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right flare: leaves the edge above heading inward, turns down.
        if f > 0 {
            path.addCurve(
                to: CGPoint(x: right, y: top + fy),
                control1: CGPoint(x: rect.maxX - ox, y: top),
                control2: CGPoint(x: right, y: top + fy - oy)
            )
        }
        path.addLine(to: CGPoint(x: right, y: rect.maxY - r * reach))
        Self.addContinuousCorner(
            to: &path,
            corner: CGPoint(x: right, y: rect.maxY),
            incoming: CGVector(dx: 0, dy: 1),
            outgoing: CGVector(dx: -1, dy: 0),
            radius: r
        )
        path.addLine(to: CGPoint(x: left + r * reach, y: rect.maxY))
        Self.addContinuousCorner(
            to: &path,
            corner: CGPoint(x: left, y: rect.maxY),
            incoming: CGVector(dx: -1, dy: 0),
            outgoing: CGVector(dx: 0, dy: -1),
            radius: r
        )
        path.addLine(to: CGPoint(x: left, y: top + fy))
        // Top-left flare, mirrored.
        if f > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: top),
                control1: CGPoint(x: left, y: top + fy - oy),
                control2: CGPoint(x: rect.minX + ox, y: top)
            )
        }
        path.closeSubpath()
        return path
    }

    /// How much the bottom corners ease into the straight edges, like Apple's
    /// own continuous corners (the MacBook's screen and notch): 0 is a plain
    /// circular arc, 0.6 is what iOS and macOS use.
    private static let cornerSmoothing: CGFloat = 0.6

    /// Adds a smoothed ("continuous") convex corner at `corner`, arriving
    /// along `incoming` and leaving along `outgoing` (unit vectors). The path
    /// must already sit (1 + smoothing) × `radius` before the corner. It's
    /// Figma's corner smoothing: a short circular arc in the middle, eased
    /// into each edge by a cubic, so the curvature builds up gradually
    /// instead of jumping from straight to round.
    private static func addContinuousCorner(
        to path: inout Path,
        corner k: CGPoint,
        incoming u: CGVector,
        outgoing v: CGVector,
        radius r: CGFloat
    ) {
        guard r > 0.01 else {
            path.addLine(to: k)
            return
        }
        let smoothing = cornerSmoothing
        func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
        let p = (1 + smoothing) * r
        let arcDegrees = 90 * (1 - smoothing)
        let arcSide = sin(radians(arcDegrees / 2)) * r * sqrt(2)
        let alpha = (90 - arcDegrees) / 2
        let p3ToP4 = r * tan(radians(alpha / 2))
        let beta = 45 * smoothing
        let c = p3ToP4 * cos(radians(beta))
        let d = c * tan(radians(beta))
        let b = (p - arcSide - c - d) / 3
        let a = 2 * b

        let start = CGPoint(x: k.x - p * u.dx, y: k.y - p * u.dy)
        func point(_ from: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: from.x + x * u.dx + y * v.dx, y: from.y + x * u.dy + y * v.dy)
        }
        func unit(_ x: CGFloat, _ y: CGFloat) -> CGVector {
            let length = max(0.0001, (x * x + y * y).squareRoot())
            return CGVector(dx: (x * u.dx + y * v.dx) / length, dy: (x * u.dy + y * v.dy) / length)
        }

        // Ease in from the edge to the start of the arc.
        let arcStart = point(start, a + b + c, d)
        path.addCurve(to: arcStart, control1: point(start, a, 0), control2: point(start, a + b, 0))
        // The arc, as a cubic.
        let arcEnd = point(arcStart, arcSide, arcSide)
        let handle = 4 / 3 * tan(radians(arcDegrees) / 4) * r
        let t1 = unit(c, d)
        let t2 = unit(d, c)
        path.addCurve(
            to: arcEnd,
            control1: CGPoint(x: arcStart.x + handle * t1.dx, y: arcStart.y + handle * t1.dy),
            control2: CGPoint(x: arcEnd.x - handle * t2.dx, y: arcEnd.y - handle * t2.dy)
        )
        // Ease out of the arc into the next edge.
        path.addCurve(
            to: point(arcEnd, d, a + b + c),
            control1: point(arcEnd, d, c),
            control2: point(arcEnd, d, b + c)
        )
    }

    /// All four corners rounded, for displays with no notch.
    private func pill(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height / 2))
        return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// A notch shape of `size`, hung from the top centre of whatever it clips:
/// the card's content is laid out at full size and cut to the moving notch.
struct NotchClip: Shape {
    var shape: NotchShape
    var size: CGSize
    /// Never shorter than this, however the spring swings: the closed
    /// notch's height. Closing, the wings' bouncy spring picks up the
    /// shape's upward speed and carried its bottom edge above the real
    /// notch for a moment before it dropped back.
    var minHeight: CGFloat = 0

    var animatableData: AnimatablePair<NotchShape.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        shape.path(in: CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: max(size.height, minHeight)))
    }
}
