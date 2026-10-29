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
    /// How far in from each side the top edge starts, so the sides curve out
    /// to full width instead of meeting the screen edge at a right angle
    /// (see `NotchShape.topInset`). Only where the HUD hangs from a physical
    /// notch and is open.
    let topInset: CGFloat

    init(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        peek: PeekContent?,
        indicators: NotchIndicators = .none
    ) {
        let metrics = geometry.metrics
        let collapsed = geometry.collapsedSize

        if isExpanded {
            mode = .card
            size = CGSize(width: metrics.cardWidth, height: metrics.panelHeight)
            bottomRadius = NotchMetrics.expandedBottomRadius
            topInset = geometry.roundsTopCorners ? 0 : Self.topInset(width: size.width, notch: metrics.notchWidth)
        } else if let peek {
            mode = .peek
            let width = min(metrics.cardWidth, max(collapsed.width, metrics.notchWidth + NotchMetrics.peekExtraWidth))
            size = CGSize(width: width, height: collapsed.height + peek.contentHeight)
            bottomRadius = NotchMetrics.peekBottomRadius
            topInset = geometry.roundsTopCorners ? 0 : Self.topInset(width: width, notch: metrics.notchWidth)
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
            topInset = 0
            // A pill is fully rounded; a physical notch keeps the small
            // bottom-only radius that matches the hardware cutout.
            bottomRadius = geometry.roundsTopCorners
                ? collapsed.height / 2
                : NotchMetrics.collapsedBottomRadius
        }
    }

    /// Never past the notch itself, so the top edge always covers it.
    private static func topInset(width: CGFloat, notch: CGFloat) -> CGFloat {
        max(0, min(NotchMetrics.topCurveWidth, (width - notch) / 2))
    }

    var isOpen: Bool { mode != .collapsed }

    /// The width content can use.
    var contentWidth: CGFloat { size.width }
}
