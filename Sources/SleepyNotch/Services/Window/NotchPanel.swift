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
    /// The bubbles beside the notch, in this view's coordinates. They take
    /// clicks but aren't hover: resting the pointer on one doesn't open the
    /// card.
    var bubbleRects: [CGRect] = []

    /// Called when the pointer moves onto or off the drawn HUD.
    var onPointerInsideChange: ((Bool) -> Void)?
    private(set) var isPointerInside = false
    /// Development only (see `Bench`): stands in for the real pointer.
    var pointerOverride: Bool?

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
        guard acceptsMouse(at: convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    /// The notch, or one of its bubbles.
    func acceptsMouse(at point: NSPoint) -> Bool {
        contains(point) || bubbleRects.contains { NSMouseInRect(point, $0, isFlipped) }
    }

    /// Mouse coordinates run one point high: with the pointer pushed against
    /// the top of the screen — exactly where you aim to open the notch — it
    /// reports y equal to the panel's top edge, which `CGRect.contains`
    /// counts as outside. That flipped hover off and on while you tried to
    /// open the card. `NSMouseInRect` is AppKit's test for mouse points:
    /// top edge in, bottom edge out.
    private func contains(_ point: NSPoint) -> Bool {
        NSMouseInRect(point, interactiveRect, isFlipped)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Events only arrive while the pointer is over the panel itself, so
        // this costs nothing while it's elsewhere.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
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

    /// Re-reads where the pointer really is rather than trusting the event.
    /// When the panel switches from click-through to taking the mouse — as
    /// the card opens under the pointer — AppKit can report an exit though
    /// the pointer never moved. Trusting it started a close, then the next
    /// move reopened the card: it appeared, vanished and came back.
    override func mouseExited(with event: NSEvent) {
        refreshPointer()
    }

    /// Re-reads where the pointer is, rather than trusting the last event —
    /// switching desktops, for one, can skip the exit event — and reports it
    /// if that changed. Returns whether it's over the drawn HUD.
    @discardableResult
    func refreshPointer() -> Bool {
        if let pointerOverride {
            setPointerInside(pointerOverride)
            return pointerOverride
        }
        guard let window else { return false }
        let inside = contains(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
        setPointerInside(inside)
        return inside
    }

    private func updatePointer(_ event: NSEvent) {
        guard pointerOverride == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        releaseHoldIfOnDrawn(point)
        setPointerInside(contains(point))
        if isPointerInside { NSCursor.arrow.set() }
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        // The panel never becomes the active window, so the app behind it
        // keeps the cursor it last set: over a search field that was the
        // text I-beam, left showing on top of the card. Over the HUD the
        // cursor is the arrow.
        if inside { NSCursor.arrow.set() }
        onPointerInsideChange?(inside)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isPointerInside { NSCursor.arrow.set() } else { super.cursorUpdate(with: event) }
    }

    // MARK: - Held area

    /// What's really drawn, when the hover area is held larger than it (a
    /// page switch shrank the card under the pointer; see
    /// `NotchInteractionState.hitHeldLarge`). Nil while not held.
    var drawnSizeWhileHeld: CGSize?
    /// The pointer reached what's really drawn: the larger area is let go,
    /// so leaving the card closes it from its real edge, not an invisible
    /// one further out.
    var onHoldReleased: (() -> Void)?

    private func releaseHoldIfOnDrawn(_ point: NSPoint) {
        guard let drawn = drawnSizeWhileHeld else { return }
        let rect = CGRect(
            x: (bounds.width - drawn.width) / 2,
            y: bounds.height - drawn.height,
            width: drawn.width,
            height: drawn.height
        )
        guard NSMouseInRect(point, rect, isFlipped) else { return }
        drawnSizeWhileHeld = nil
        interactiveSize = drawn
        onHoldReleased?()
    }
}
