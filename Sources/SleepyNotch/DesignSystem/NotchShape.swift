import SwiftUI

// Mirrors the physical MacBook notch:
// - flat top edge, flush with the screen top
// - rounded bottom corners only
// - grows downward into a card when expanded
//
// The corners use cubic Béziers with the standard circular-arc control offset
// (0.5523 * radius) rather than a plain quadratic. A quadratic cannot represent
// a circular arc, so the silhouette kinks slightly where the curve meets the
// straight edge — visible against the hardware cutout it has to sit inside.
public struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    /// Control-point offset for a cubic approximation of a quarter circle.
    private static let arcConstant: CGFloat = 0.5523

    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let r = min(bottomRadius, insetRect.width / 2, max(insetRect.height, 0))
        guard r > 0 else {
            path.addRect(insetRect)
            return path
        }
        // Control points pull toward the inner corner of the fillet.
        let k = r * Self.arcConstant

        // Top-left
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        // Top edge — flat, flush with the screen top
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))
        // Down the right edge to the fillet
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - r))
        // Bottom-right corner
        path.addCurve(
            to: CGPoint(x: insetRect.maxX - r, y: insetRect.maxY),
            control1: CGPoint(x: insetRect.maxX, y: insetRect.maxY - r + k),
            control2: CGPoint(x: insetRect.maxX - r + k, y: insetRect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: insetRect.minX + r, y: insetRect.maxY))
        // Bottom-left corner
        path.addCurve(
            to: CGPoint(x: insetRect.minX, y: insetRect.maxY - r),
            control1: CGPoint(x: insetRect.minX + r - k, y: insetRect.maxY),
            control2: CGPoint(x: insetRect.minX, y: insetRect.maxY - r + k)
        )
        path.closeSubpath()

        return path
    }

    public func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
