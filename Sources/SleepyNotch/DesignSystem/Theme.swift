import SwiftUI

/// Centralised colours and metrics.
///
/// Previously the source accent was an identical three-way `switch` duplicated
/// across `NotchView`, `CompactNotchView` and `ExpandedPlayerView`, and the
/// notch fill was a hand-tuned near-black. Both live here now.
enum Theme {
    // MARK: - Notch surface

    /// True black, collapsed *and* open. The MacBook notch is a display
    /// cutout — the panel is simply off there — so anything less than
    /// `#000000` shows the hardware notch as a black block. The open card and
    /// peeks grow out of the notch with the cutout still in their top edge, so
    /// they have to be pure black too; a lifted card colour made the camera
    /// housing visible inside it. Depth comes from the edge highlight and the
    /// glow instead.
    static let notchFill = Color.black

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

    // MARK: - Controls

    /// Scrubber, waveform and progress ring. White, like the system's own
    /// Now Playing controls; colour is reserved for status.
    static let controlTint = Color.white

    // MARK: - Status

    /// macOS's own system colours, so status reads exactly like the rest of
    /// the OS (battery menu, Control Center).
    enum Status {
        static let charging = Color(nsColor: .systemGreen)
        static let warning = Color(nsColor: .systemOrange)
        static let critical = Color(nsColor: .systemRed)
    }

    static let hairline = Color.white.opacity(0.12)
    static let scrim = Color.white.opacity(0.06)
}
