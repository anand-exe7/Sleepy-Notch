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
    /// Bubbles split off the closed notch's sides (see `NotchBubble`). Only
    /// beside a physical notch; tucked away (progress 0) whenever it's open.
    let leadingBubble: NotchBubble
    let trailingBubble: NotchBubble

    init(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        peek: PeekContent?,
        indicators: NotchIndicators = .none,
        nowPlaying: Bool = false,
        showsBubbles: Bool = true
    ) {
        let metrics = geometry.metrics
        let collapsed = geometry.collapsedSize

        // Bubbles keep their size when tucked away, so they come and go by
        // sliding and growing rather than changing shape.
        let physical = geometry.presence == .physical
        let bubbleHeight = StatusWingsView.bubbleHeight(forHeight: collapsed.height)
        func bubble(shown: Bool, width: CGFloat) -> NotchBubble {
            guard physical else { return .hidden }
            return NotchBubble(
                progress: shown && !isExpanded && peek == nil && showsBubbles ? 1 : 0,
                width: width,
                height: bubbleHeight,
                centerY: collapsed.height / 2
            )
        }
        leadingBubble = bubble(
            shown: indicators.hasLeadingBubble(nowPlaying: nowPlaying),
            width: StatusWingsView.privacyBubbleWidth(for: indicators, height: bubbleHeight)
        )
        trailingBubble = bubble(
            shown: indicators.hasTrailingBubble(nowPlaying: nowPlaying),
            width: bubbleHeight
        )

        if isExpanded {
            mode = .card
            size = metrics.cardSize
            bottomRadius = NotchMetrics.expandedBottomRadius
            topFlare = geometry.roundsTopCorners ? 0 : NotchMetrics.expandedTopFlare
        } else if let peek {
            mode = .peek
            let flare = geometry.roundsTopCorners ? 0 : NotchMetrics.peekTopFlare
            let width = min(metrics.panelWidth, max(collapsed.width, metrics.notchWidth + peek.extraWidth) + 2 * flare)
            size = CGSize(width: width, height: collapsed.height + peek.contentHeight)
            bottomRadius = peek.bottomRadius
            topFlare = flare
        } else {
            // Closed, the HUD is exactly the hardware notch and draws nothing
            // (the cutout has no pixels anyway), so closing the card leaves no
            // trace. A floating pill on a notch-less display is the exception.
            mode = .collapsed
            // Status beside a physical notch widens it into wings, evenly
            // either side so the camera stays centred. A pill shows status
            // inside itself.
            let wing = geometry.presence == .physical
                ? StatusWingsView.wingWidth(for: indicators, nowPlaying: nowPlaying)
                : 0
            // With wings, a small flare blends the widened notch into the
            // screen edge, like the open card's.
            let flare = wing > 0 ? NotchMetrics.wingsTopFlare : 0
            size = CGSize(width: collapsed.width + 2 * (wing + flare), height: collapsed.height)
            topFlare = flare
            // A pill is fully rounded; a physical notch keeps the small
            // bottom-only radius that matches the hardware cutout.
            bottomRadius = geometry.roundsTopCorners
                ? collapsed.height / 2
                : NotchMetrics.collapsedBottomRadius
        }
    }

    var isOpen: Bool { mode != .collapsed }

    /// The silhouette for this layout.
    func shape(roundsTopCorners: Bool) -> NotchShape {
        NotchShape(
            bottomRadius: bottomRadius,
            topFlare: topFlare,
            roundsTopCorners: roundsTopCorners,
            leadingBubble: leadingBubble,
            trailingBubble: trailingBubble
        )
    }

    /// The width content can use: the body, between the flares.
    var contentWidth: CGFloat { size.width - 2 * topFlare }
}
