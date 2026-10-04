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
struct NotchMetrics: Equatable {
    // Expansion deltas. These are ours to choose — they don't depend on the
    // hardware notch.
    static let expandedExtraWidth: CGFloat = 220
    static let expandedHeight: CGFloat = 175
    static let expandedBottomRadius: CGFloat = 22
    static let collapsedBottomRadius: CGFloat = 10

    /// Fallback for displays with no notch at all.
    static let fallbackNotchWidth: CGFloat = 179
    static let fallbackNotchHeight: CGFloat = 32

    /// Collapsed size when there's no hardware notch to sit inside, so the HUD
    /// floats below the menu bar as a pill instead of pretending to be a cutout.
    static let pillWidth: CGFloat = 320
    static let pillHeight: CGFloat = 42

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

    /// The card the SwiftUI content lays out inside.
    var cardWidth: CGFloat { panelWidth }

    /// The expanded card size. Collapsed size comes from `DisplayGeometry`,
    /// since it depends on whether the display actually has a notch.
    func size(isExpanded: Bool) -> NotchSize {
        isExpanded
            ? NotchSize(width: panelWidth, height: panelHeight)
            : NotchSize(width: notchWidth, height: notchHeight)
    }
}

/// Expanded-or-collapsed dimensions of the HUD.
struct NotchSize {
    let width: CGFloat
    let height: CGFloat
}
