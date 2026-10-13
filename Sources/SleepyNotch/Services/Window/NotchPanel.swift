import AppKit

/// The panel's content view: a pass-through layer that only accepts mouse
/// events where something is actually drawn, and the one place hover is
/// decided.
///
/// The window itself is allocated `panelWidth x panelHeight` permanently so
/// the SwiftUI spring is the only animation in play. That means when collapsed,
/// a large invisible rectangle sits over the menu bar and the desktop beneath
/// the HUD. At `.statusBar` level it would swallow clicks meant for nearby menu
/// bar items — battery, Wi-Fi, clock — because a borderless clear window
/// hit-tests its entire bounds by default.
///
/// So clicks and hover both use the rectangle the HUD currently occupies —
/// the notch (or pill) while collapsed, the peek, or the whole card —
/// anchored to the top centre. Deciding hover here, against the same
/// rectangle, means the two can never disagree, and it doesn't depend on how
/// SwiftUI lays out the views drawn inside.
final class NotchHitView: NSView {
    /// The size of what's drawn right now. Set by the SwiftUI layer.
    var interactiveSize: CGSize = .zero

    /// Called when the pointer moves onto or off the drawn HUD.
    var onPointerInsideChange: ((Bool) -> Void)?
    private(set) var isPointerInside = false

    private var trackingArea: NSTrackingArea?

    /// What's drawn, in this view's coordinates: top-centred.
    var interactiveRect: CGRect {
        CGRect(
            x: (bounds.width - interactiveSize.width) / 2,
            y: bounds.height - interactiveSize.height,
            width: interactiveSize.width,
            height: interactiveSize.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Events only arrive while the pointer is over the panel itself, so
        // this costs nothing while it's elsewhere.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(event)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    /// Whether the pointer is over the drawn HUD right now, from its current
    /// location rather than the last event.
    func pointerIsInside() -> Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return interactiveRect.contains(point)
    }

    private func updatePointer(_ event: NSEvent) {
        setPointerInside(interactiveRect.contains(convert(event.locationInWindow, from: nil)))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        onPointerInsideChange?(inside)
    }
}
