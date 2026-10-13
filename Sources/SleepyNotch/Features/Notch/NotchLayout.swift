import CoreGraphics

/// What the notch is showing, and the size and corner radius that go with
/// it. Pure geometry, kept apart from the view so it can be reasoned about
/// (and tested) on its own.
struct NotchLayout: Equatable {
    /// The card always wins over a peek: opening it holds peeks back (see
    /// `PeekCenter.setHeld`).
    enum Mode: Equatable {
        case collapsed
        case peek
        case card
    }

    let mode: Mode
    /// The HUD's outer size in this mode. The panel never resizes; this is
    /// what the SwiftUI springs animate between.
    let size: CGSize
    let bottomRadius: CGFloat
    /// The outward flare at each top corner, inside `size`. Only where the
    /// HUD hangs from the screen edge (a physical notch) and is open.
    let topFlare: CGFloat

    init(geometry: DisplayGeometry, isExpanded: Bool, peek: PeekContent?) {
        let metrics = geometry.metrics
        let collapsed = geometry.collapsedSize

        if isExpanded {
            mode = .card
            size = CGSize(width: metrics.panelWidth, height: metrics.panelHeight)
            bottomRadius = NotchMetrics.expandedBottomRadius
            topFlare = geometry.roundsTopCorners ? 0 : NotchMetrics.expandedTopFlare
        } else if let peek {
            mode = .peek
            let flare = geometry.roundsTopCorners ? 0 : NotchMetrics.peekTopFlare
            let width = peek.isWide
                ? metrics.panelWidth
                : min(metrics.panelWidth, max(collapsed.width, metrics.notchWidth + NotchMetrics.peekExtraWidth) + 2 * flare)
            size = CGSize(width: width, height: collapsed.height + peek.contentHeight)
            bottomRadius = NotchMetrics.peekBottomRadius
            topFlare = flare
        } else {
            // Closed, the HUD is exactly the hardware notch and draws nothing
            // (the cutout has no pixels anyway), so closing the card leaves no
            // trace. A floating pill on a notch-less display is the exception.
            mode = .collapsed
            size = collapsed
            topFlare = 0
            // A pill is fully rounded; a physical notch keeps the small
            // bottom-only radius that matches the hardware cutout.
            bottomRadius = geometry.roundsTopCorners
                ? collapsed.height / 2
                : NotchMetrics.collapsedBottomRadius
        }
    }

    var isOpen: Bool { mode != .collapsed }

    /// The width content can use: the body, between the flares.
    var contentWidth: CGFloat { size.width - 2 * topFlare }
}
