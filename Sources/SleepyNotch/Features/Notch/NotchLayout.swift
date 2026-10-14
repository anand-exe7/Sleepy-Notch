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
    /// Where the flares sit (see `NotchShape.shoulder`): the menu bar's
    /// bottom edge when it's dark, the screen edge when it's light.
    let shoulder: CGFloat

    init(
        geometry: DisplayGeometry,
        menuBarIsDark: Bool,
        isExpanded: Bool,
        peek: PeekContent?,
        indicators: NotchIndicators = .none
    ) {
        let metrics = geometry.metrics
        let collapsed = geometry.collapsedSize
        shoulder = menuBarIsDark && !geometry.roundsTopCorners ? metrics.notchHeight : 0

        if isExpanded {
            mode = .card
            size = CGSize(width: metrics.panelWidth, height: metrics.panelHeight)
            bottomRadius = NotchMetrics.expandedBottomRadius
            topFlare = geometry.roundsTopCorners ? 0 : NotchMetrics.expandedTopFlare
        } else if let peek {
            mode = .peek
            let flare = geometry.roundsTopCorners ? 0 : NotchMetrics.peekTopFlare
            let width = min(metrics.panelWidth, max(collapsed.width, metrics.notchWidth + NotchMetrics.peekExtraWidth) + 2 * flare)
            size = CGSize(width: width, height: collapsed.height + peek.contentHeight)
            bottomRadius = NotchMetrics.peekBottomRadius
            topFlare = flare
        } else {
            // Closed, the HUD is exactly the hardware notch and draws nothing
            // (the cutout has no pixels anyway), so closing the card leaves no
            // trace. A floating pill on a notch-less display is the exception.
            mode = .collapsed
            // Status beside a physical notch widens it into wings, evenly
            // either side so the camera stays centred. A pill shows status
            // inside itself.
            let wing = geometry.presence == .physical ? StatusWingsView.wingWidth(for: indicators) : 0
            size = CGSize(width: collapsed.width + 2 * wing, height: collapsed.height)
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
