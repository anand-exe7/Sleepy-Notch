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
        arrangement: IslandArrangement = .empty,
        bubbleFaces: [NotchSide: BubbleFace] = [:],
        showsWings: Bool = true,
        showsBubbles: Bool = true,
        peekSize: CGSize? = nil
    ) {
        let metrics = geometry.metrics
        let collapsed = geometry.collapsedSize

        // Bubbles keep their size when tucked away, so they come and go by
        // sliding and growing rather than changing shape.
        let physical = geometry.presence == .physical
        let bubbleHeight = StatusWingsView.bubbleHeight(forHeight: collapsed.height)
        // Bubbles stay beside the notch while it's open too (a peek, the
        // card, an activity opened from its bubble), riding its sides. Only
        // the welcome has the notch to itself.
        let bubblesAllowed = physical && showsBubbles && peek != .welcome
        func bubble(_ side: NotchSide) -> NotchBubble {
            guard physical, let face = arrangement.bubble(side)?.face ?? bubbleFaces[side] else { return .hidden }
            return NotchBubble(
                progress: bubblesAllowed && arrangement.bubble(side)?.visible == true ? 1 : 0,
                width: StatusWingsView.bubbleWidth(for: face, height: bubbleHeight),
                height: bubbleHeight,
                centerY: collapsed.height / 2
            )
        }
        leadingBubble = bubble(.leading)
        trailingBubble = bubble(.trailing)

        if isExpanded {
            mode = .card
            size = metrics.cardSize
            bottomRadius = NotchMetrics.expandedBottomRadius
            topFlare = geometry.roundsTopCorners ? 0 : NotchMetrics.expandedTopFlare
        } else if let peek {
            mode = .peek
            let flare = geometry.roundsTopCorners ? 0 : NotchMetrics.peekTopFlare
            // Most peeks have a set size; an opened activity brings its own,
            // fitted to what it shows.
            let body = peekSize?.width ?? metrics.notchWidth + peek.extraWidth
            let width = min(metrics.panelWidth, max(collapsed.width, body) + 2 * flare)
            size = CGSize(width: width, height: collapsed.height + (peekSize?.height ?? peek.contentHeight))
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
            let wing = geometry.presence == .physical && showsWings
                ? StatusWingsView.wingWidth(for: arrangement, indicators: indicators)
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

    /// Where a bubble on `side` measures from, in a panel `panelWidth` wide.
    func bubbleAnchor(_ side: NotchSide, panelWidth: CGFloat) -> CGFloat {
        let body = panelWidth / 2 + side.sign * contentWidth / 2
        return NotchBubble.anchor(bodyEdge: body, flare: topFlare, side: side)
    }

    /// Where the bubbles that are showing rest, in panel coordinates (top
    /// left origin): the panel takes clicks there.
    func bubbleRects(panelWidth: CGFloat) -> [CGRect] {
        [(NotchSide.leading, leadingBubble), (.trailing, trailingBubble)].compactMap { side, bubble in
            guard bubble.isShown else { return nil }
            var resting = bubble
            resting.progress = 1
            return resting.frame(side: side, bodyEdge: bubbleAnchor(side, panelWidth: panelWidth), top: 0)
        }
    }
}
