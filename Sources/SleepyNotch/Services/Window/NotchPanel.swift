import AppKit

/// The panel's content view: a pass-through layer that only accepts mouse
/// events where something is actually drawn.
///
/// The window itself is allocated `panelWidth x panelHeight` permanently so
/// the SwiftUI spring is the only animation in play. That means when collapsed,
/// a large invisible rectangle sits over the menu bar and the desktop beneath
/// the HUD. At `.statusBar` level it would swallow clicks meant for nearby menu
/// bar items — battery, Wi-Fi, clock — because a borderless clear window
/// hit-tests its entire bounds by default.
///
/// Collapsed, only the notch (or pill) is interactive. Expanded, the whole card
/// is real, so the whole card accepts clicks.
final class NotchHitView: NSView {
    /// Mirrors the SwiftUI expansion state.
    var isNotchCollapsed: Bool = true

    /// Updated whenever display geometry is re-measured.
    var geometry: DisplayGeometry = .fallback

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard isNotchCollapsed else { return hit }
        return geometry.collapsedRect(in: bounds.size).contains(point) ? hit : nil
    }
}
