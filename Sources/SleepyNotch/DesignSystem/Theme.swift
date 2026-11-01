import SwiftUI

/// The app's colours in one place, so every view draws the notch and its
/// controls the same way.
enum Theme {
    // MARK: - Notch surface

    /// True black. The MacBook notch is a display cutout — the panel is
    /// simply off there — so anything less than `#000000` beside it shows the
    /// hardware notch as a black block. The Black finish uses it for the
    /// whole body; Liquid Glass keeps it for the strip along the notch (see
    /// `NotchSurface`).
    static let notchFill = Color.black

    // MARK: - Foreground

    /// Text sits on a near-black surface, so contrast is driven by opacity over
    /// white. The previous values ran down to 0.35, which measured roughly
    /// 3.2:1 — under the WCAG AA 4.5:1 floor for body text.
    enum Text {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.72)
        static let tertiary = Color.white.opacity(0.55)
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
