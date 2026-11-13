import CoreGraphics

/// Single source of truth for notch geometry.
///
/// Everything derives from the measured `notchWidth` / `notchHeight`, so a
/// 14" or 16" notch produces a correctly sized card and hit region. Sizes
/// tuned by hand for one MacBook only look right on that one.
struct NotchMetrics: Equatable {
    // Expansion deltas. These are ours to choose — they don't depend on the
    // hardware notch. Proportioned after Droppy's card: compact, with the
    // cover sitting beside the camera rather than below it.
    /// The open card's body is this much wider than the notch: 85pt either
    /// side, room for the cover beside the camera.
    static let cardExtraWidth: CGFloat = 170
    /// How far the open card reaches below the notch.
    static let cardBodyHeight: CGFloat = 143
    /// Added under the notch when the card has more than one page: a
    /// small page pill sits centred right below the camera and the page
    /// moves down by this (see `CardTabBar`).
    static let tabStripRoom: CGFloat = 28
    /// One page button's size in the pill.
    static let tabButton = CGSize(width: 30, height: 22)
    /// The Controls page: one row of buttons, so the card is only as tall
    /// as that, not the music card's height.
    static let controlsBodyHeight: CGFloat = 104
    /// The Widgets page opens big: this much wider than the card body, and
    /// this tall below the notch (its tab bar included).
    static let widgetsExtraWidth: CGFloat = 150
    static let widgetsBodyHeight: CGFloat = 208
    static let expandedBottomRadius: CGFloat = 40
    static let collapsedBottomRadius: CGFloat = 10
    /// Open, the top corners flare outward into the screen edge by this much
    /// on each side, sweeping about 1.75 times as far down the side (see
    /// `NotchShape`), like Droppy's.
    static let expandedTopFlare: CGFloat = 18

    /// A peek widens the notch by this much and drops a row below it.
    /// Everything stays inside the panel.
    static let peekExtraWidth: CGFloat = 190
    static let peekBottomRadius: CGFloat = 26
    static let peekTopFlare: CGFloat = 16
    /// The tallest peek's row: the charge opened with the camera and mic
    /// under it (see `ActivityDetailView.size`). Headphones are 150.
    static let tallestPeekHeight: CGFloat = 176
    /// Spare room under the tallest peek, so its opening spring can stretch
    /// past its size and the rounded bottom is never cut off by the panel.
    static let springRoom: CGFloat = 24
    /// Closed with something beside the camera (now playing, status), the
    /// widened notch flares into the screen edge by this much.
    static let wingsTopFlare: CGFloat = 9

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

    /// The open card's body, between its flares. The card's content lays
    /// out at this width.
    var cardWidth: CGFloat { notchWidth + Self.cardExtraWidth }

    /// The open card's outer size, flares included.
    var cardSize: CGSize {
        CGSize(width: cardWidth + 2 * Self.expandedTopFlare, height: notchHeight + Self.cardBodyHeight)
    }

    /// The panel is allocated room for the open card and the largest peek
    /// for the whole lifetime of the app. It's borderless and transparent,
    /// so the spare area is invisible, and `NotchShape` clips the SwiftUI
    /// content to the notch silhouette. Resizing the panel instead would mean
    /// two independent animation systems (an `NSAnimationContext` frame
    /// change and a SwiftUI spring) racing each other, which clipped the
    /// content mid-animation.
    /// The big Widgets page's body width (see `widgetsExtraWidth`).
    var widgetsWidth: CGFloat { cardWidth + Self.widgetsExtraWidth }

    var panelWidth: CGFloat {
        max(cardSize.width + Self.widgetsExtraWidth, notchWidth + Self.peekExtraWidth + 2 * Self.peekTopFlare)
            // Room for a bubble either side, beside the open card too.
            + 2 * Self.bubbleReach
    }

    /// How far past the card's side a bubble can reach (see `NotchBubble`).
    static let bubbleReach: CGFloat = 76

    var panelHeight: CGFloat {
        max(notchHeight + Self.widgetsBodyHeight + Self.tabStripRoom, cardSize.height + Self.tabStripRoom, notchHeight + Self.tallestPeekHeight) + Self.springRoom
    }
}
