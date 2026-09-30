import CoreGraphics

/// Single source of truth for notch geometry.
///
/// The notch dimensions, the expansion deltas, and the card width were
/// previously duplicated across `NotchWindowController`, `NotchView` and
/// `CompactNotchView`. They disagreed in ways that only showed up on MacBook
/// sizes other than the one they were tuned on — the expanded card hardcoded a
/// width of 399pt, which is only correct when the notch is exactly 179pt wide.
///
/// Everything derives from the measured `notchWidth` / `notchHeight`, so a
/// 14" or 16" notch produces a correctly sized card and hit region.
struct NotchMetrics {
    // Expansion deltas. These are ours to choose — they don't depend on the
    // hardware notch.
    static let expandedExtraWidth: CGFloat = 220
    static let expandedHeight: CGFloat = 175
    static let expandedBottomRadius: CGFloat = 22
    static let collapsedBottomRadius: CGFloat = 10

    /// Fallback for displays with no notch at all.
    static let fallbackNotchWidth: CGFloat = 179
    static let fallbackNotchHeight: CGFloat = 32

    /// The physical notch, as measured from the screen.
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    static let fallback = NotchMetrics(
        notchWidth: fallbackNotchWidth,
        notchHeight: fallbackNotchHeight
    )

    // MARK: - Derived sizes

    /// The panel is allocated its full expanded size for the whole lifetime of
    /// the app. It's borderless and transparent, so the oversized area is
    /// invisible, and `NotchShape` clips the SwiftUI content to the notch
    /// silhouette. Resizing the panel instead would mean two independent
    /// animation systems (a 0.25s `NSAnimationContext` frame change and a
    /// 0.38s SwiftUI spring) racing each other, which clipped the content
    /// mid-animation.
    var panelWidth: CGFloat { notchWidth + Self.expandedExtraWidth }
    var panelHeight: CGFloat { Self.expandedHeight }

    /// Collapsed: exactly the hardware notch, so the HUD is pixel-aligned with
    /// the physical cutout and never overhangs onto the menu bar.
    var collapsedWidth: CGFloat { notchWidth }
    var collapsedHeight: CGFloat { notchHeight }

    /// The card the SwiftUI content lays out inside.
    var cardWidth: CGFloat { panelWidth }

    func bottomCornerRadius(isExpanded: Bool) -> CGFloat {
        isExpanded ? Self.expandedBottomRadius : Self.collapsedBottomRadius
    }

    func size(isExpanded: Bool) -> (width: CGFloat, height: CGFloat) {
        isExpanded ? (panelWidth, panelHeight) : (collapsedWidth, collapsedHeight)
    }
}
