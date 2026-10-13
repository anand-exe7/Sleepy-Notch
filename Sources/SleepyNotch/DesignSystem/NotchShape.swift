import SwiftUI

// Mirrors the physical MacBook notch, and grows out of it:
// - the top edge sits flush with the screen top
// - open, the top corners flare outward in a concave curve, so the card
//   pours out of the bezel instead of meeting it at a hard right angle
// - rounded bottom corners
//
// The corners use cubic Béziers with the standard circular-arc control offset
// (0.5523 * radius) rather than a plain quadratic. A quadratic cannot represent
// a circular arc, so the silhouette kinks slightly where the curve meets the
// straight edge — visible against the hardware cutout it has to sit inside.
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

    /// Control-point offset for a cubic approximation of a quarter circle.
    private static let arcConstant: CGFloat = 0.5523

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topFlare) }
        set {
            bottomRadius = newValue.first
            topFlare = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        return roundsTopCorners ? pill(in: rect) : flared(in: rect)
    }

    /// Flat top flush with the screen, concave flares into it, rounded bottom.
    private func flared(in rect: CGRect) -> Path {
        let f = max(0, min(topFlare, rect.width / 4, rect.height / 2))
        let left = rect.minX + f
        let right = rect.maxX - f
        let r = max(0, min(bottomRadius, (right - left) / 2, rect.height - f))
        let kf = f * Self.arcConstant
        let k = r * Self.arcConstant

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right flare: leaves the screen edge heading inward, turns down.
        if f > 0 {
            path.addCurve(
                to: CGPoint(x: right, y: rect.minY + f),
                control1: CGPoint(x: rect.maxX - kf, y: rect.minY),
                control2: CGPoint(x: right, y: rect.minY + f - kf)
            )
        }
        path.addLine(to: CGPoint(x: right, y: rect.maxY - r))
        // Bottom-right
        path.addCurve(
            to: CGPoint(x: right - r, y: rect.maxY),
            control1: CGPoint(x: right, y: rect.maxY - r + k),
            control2: CGPoint(x: right - r + k, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        // Bottom-left
        path.addCurve(
            to: CGPoint(x: left, y: rect.maxY - r),
            control1: CGPoint(x: left + r - k, y: rect.maxY),
            control2: CGPoint(x: left, y: rect.maxY - r + k)
        )
        path.addLine(to: CGPoint(x: left, y: rect.minY + f))
        // Top-left flare, mirrored.
        if f > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control1: CGPoint(x: left, y: rect.minY + f - kf),
                control2: CGPoint(x: rect.minX + kf, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }

    /// All four corners rounded, for displays with no notch.
    private func pill(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height / 2))
        return Path(roundedRect: rect, cornerRadius: r, style: .circular)
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
