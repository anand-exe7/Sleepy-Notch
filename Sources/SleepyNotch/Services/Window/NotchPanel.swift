import AppKit

/// The panel's content view: a pass-through layer that only accepts mouse
/// events where something is actually drawn.
///
/// The window itself is allocated `panelWidth x panelHeight` permanently so
/// the SwiftUI spring is the only animation in play. That means when collapsed,
/// a large invisible rectangle sits over the menu bar and the desktop beneath
/// the notch. At `.statusBar` level it would swallow clicks meant for nearby
/// menu bar items — battery, Wi-Fi, clock — because a borderless clear window
/// hit-tests its entire bounds by default.
///
/// Collapsed, only the physical notch silhouette is interactive. Expanded, the
/// whole card is real, so the whole card accepts clicks.
final class NotchHitView: NSView {
    /// Mirrors the SwiftUI expansion state.
    var isNotchCollapsed: Bool = true

    /// Set by the window controller whenever geometry is (re)measured.
    var metrics: NotchMetrics = .fallback

    /// The hardware notch expressed in this view's coordinate space.
    ///
    /// AppKit's origin is bottom-left, so the notch — which hugs the top of the
    /// screen — occupies the *top* of the view, not the bottom.
    private var notchSilhouette: CGRect {
        CGRect(
            x: (bounds.width - metrics.notchWidth) / 2,
            y: bounds.height - metrics.notchHeight,
            width: metrics.notchWidth,
            height: metrics.notchHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard isNotchCollapsed else { return hit }
        return notchSilhouette.contains(point) ? hit : nil
    }
}
