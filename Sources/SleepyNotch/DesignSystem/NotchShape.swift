import SwiftUI

// Mirrors the physical MacBook notch, and grows out of it:
// - the top edge sits flush with the screen top
// - open, the top edge starts a little in from each side, and the sides
//   curve smoothly out from there to the card's full width — small at the
//   outside, growing inward. Nothing reaches wider than the card itself
// - rounded bottom corners
//
// The curves use cubic Béziers with the standard circular-arc control offset
// (0.5523 * radius) rather than a plain quadratic. A quadratic cannot represent
// a circular arc, so the silhouette kinks slightly where the curve meets the
// straight edge — visible against the hardware cutout it has to sit inside.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    /// How far in from each side the top edge starts; the sides curve out
    /// from there. Zero while collapsed, so the closed notch matches the
    /// hardware cutout.
    var topInset: CGFloat = 0
    /// How far down the sides take to curve out to full width. The menu
    /// bar's height, so the card is full width by the time it's below it.
    var taperDepth: CGFloat = 0
    /// The hardware notch is cut into the top edge, so its top corners meet
    /// the screen edge. The floating-pill fallback has no screen edge to blend
    /// into, so all four corners are rounded and the taper is ignored.
    var roundsTopCorners: Bool = false
    var insetAmount: CGFloat = 0

    /// Control-point offset for a cubic approximation of a quarter circle.
    private static let arcConstant: CGFloat = 0.5523

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topInset) }
        set {
            bottomRadius = newValue.first
            topInset = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        return roundsTopCorners ? pill(in: rect) : tapered(in: rect)
    }

    /// Top flush with the screen, sides curving out to full width, rounded
    /// bottom.
    private func tapered(in rect: CGRect) -> Path {
        let inset = max(0, min(topInset, rect.width / 2))
        let depth = inset > 0 ? max(0, min(taperDepth, rect.height - bottomRadius)) : 0
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height - depth))
        let k = r * Self.arcConstant
        let kx = inset * Self.arcConstant
        let ky = depth * Self.arcConstant

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        // Right side: heads outward along the screen edge, then turns down
        // into the card's side.
        if depth > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + depth),
                control1: CGPoint(x: rect.maxX - inset + kx, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + depth - ky)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right
        path.addCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - r + k),
            control2: CGPoint(x: rect.maxX - r + k, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control1: CGPoint(x: rect.minX + r - k, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - r + k)
        )
        // Left side, mirrored: up the side, then curving in along the top.
        if depth > 0 {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + depth))
            path.addCurve(
                to: CGPoint(x: rect.minX + inset, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.minY + depth - ky),
                control2: CGPoint(x: rect.minX + inset - kx, y: rect.minY)
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
