import SwiftUI

/// Centralised colours and metrics.
///
/// Previously the source accent was an identical three-way `switch` duplicated
/// across `NotchView`, `CompactNotchView` and `ExpandedPlayerView`, and the
/// notch fill was a hand-tuned near-black. Both live here now.
enum Theme {
    // MARK: - Notch surface

    /// True black. The MacBook notch is a display cutout — the panel is simply
    /// off there — so anything less than `#000000` shows as a faintly tinted
    /// rectangle against the hardware, especially next to a light wallpaper or
    /// a light menu bar.
    static let notchFill = Color.black

    /// Expanded, the card is lifted a hair off pure black so it reads as a
    /// raised surface rather than a hole in the desktop. The transition between
    /// the two is animated so the morph doesn't pop.
    static let cardFill = Color(red: 0.055, green: 0.055, blue: 0.07)

    static func fill(isExpanded: Bool) -> Color {
        isExpanded ? cardFill : notchFill
    }

    // MARK: - Source accent

    static func accent(for source: MusicSource) -> Color {
        switch source {
        case .appleMusic: return Color(red: 1.0, green: 0.27, blue: 0.42)
        case .spotify: return Color(red: 0.11, green: 0.84, blue: 0.42)
        case .demo: return Color(red: 0.33, green: 0.58, blue: 1.0)
        }
    }

    // MARK: - Foreground

    /// Text sits on a near-black surface, so contrast is driven by opacity over
    /// white. The previous values ran down to 0.35, which measured roughly
    /// 3.2:1 — under the WCAG AA 4.5:1 floor for body text.
    enum Text {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.72)
        static let tertiary = Color.white.opacity(0.55)
        /// For the 9pt timestamp labels, the smallest text in the card.
        static let caption = Color.white.opacity(0.6)
    }

    // MARK: - Status

    /// Colours for system peeks (charging, low battery, devices).
    enum Status {
        static let charging = Color(red: 0.2, green: 0.9, blue: 0.45)
        static let warning = Color(red: 1.0, green: 0.62, blue: 0.16)
        static let device = Color(red: 0.55, green: 0.75, blue: 1.0)
    }

    static let hairline = Color.white.opacity(0.12)
    static let scrim = Color.white.opacity(0.06)
}
