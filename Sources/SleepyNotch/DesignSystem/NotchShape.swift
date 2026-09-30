import SwiftUI

// Custom shape that mirrors the physical Mac notch:
// - Flat top edge (flush with screen top)
// - Rounded bottom corners only
// - When expanded, grows downward like the notch is stretching
public struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0
    
    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    
    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let br = min(bottomRadius, insetRect.width / 2, max(insetRect.height, 0))
        
        // Start at top-left
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        // Top edge (flat - flush with screen top)
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))
        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY),
            control: CGPoint(x: insetRect.maxX, y: insetRect.maxY)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: insetRect.minX + br, y: insetRect.maxY))
        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX, y: insetRect.maxY - br),
            control: CGPoint(x: insetRect.minX, y: insetRect.maxY)
        )
        // Left edge back to top
        path.closeSubpath()
        
        return path
    }
    
    public func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
