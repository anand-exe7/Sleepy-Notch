import AppKit
import CoreGraphics

/// How the HUD is anchored on the current display.
enum NotchPresence: Equatable {
    /// The display has a real hardware notch; the HUD sits flush inside it.
    case physical
    /// No notch on this display; the HUD floats below the menu bar as a pill.
    case none
}

/// Everything needed to place the panel and the collapsed HUD on one display.
struct DisplayGeometry: Equatable {
    let presence: NotchPresence
    let metrics: NotchMetrics
    /// Horizontal centre of the collapsed HUD, in screen coordinates.
    let centerX: CGFloat
    /// Top edge the panel is anchored to, in screen coordinates. For a physical
    /// notch this is the top of the screen; for the pill fallback it's the top
    /// of `visibleFrame`, i.e. underneath the menu bar.
    let topY: CGFloat
    let frame: CGRect
    let visibleFrame: CGRect

    static let fallback = DisplayGeometry(
        presence: .physical,
        metrics: .fallback,
        centerX: 0,
        topY: 0,
        frame: .zero,
        visibleFrame: .zero
    )

    // MARK: - Layout

    var panelSize: CGSize {
        CGSize(width: metrics.panelWidth, height: metrics.panelHeight)
    }

    /// Collapsed size: exactly the hardware notch, or the pill.
    var collapsedSize: CGSize {
        switch presence {
        case .physical:
            return CGSize(width: metrics.notchWidth, height: metrics.notchHeight)
        case .none:
            return CGSize(width: NotchMetrics.pillWidth, height: NotchMetrics.pillHeight)
        }
    }

    /// The physical notch is cut into the top edge, so only its bottom corners
    /// are rounded. A floating pill is rounded on all four.
    var roundsTopCorners: Bool {
        presence == .none
    }

    var panelFrame: CGRect {
        CGRect(
            x: centerX - metrics.panelWidth / 2,
            y: topY - metrics.panelHeight,
            width: metrics.panelWidth,
            height: metrics.panelHeight
        )
    }

    /// Where the collapsed HUD is drawn — and therefore where the panel accepts
    /// mouse events. In a view of `size`, anchored to the top edge.
    func collapsedRect(in size: CGSize) -> CGRect {
        let c = collapsedSize
        return CGRect(
            x: (size.width - c.width) / 2,
            y: size.height - c.height,
            width: c.width,
            height: c.height
        )
    }
}

/// Picks the display the HUD should live on.
///
/// Deliberately does *not* use `NSScreen.main`, which resolves to the display
/// containing the key window — for an accessory app that never becomes active,
/// that's the display under the cursor. Any display reconfiguration would
/// relocate the notch HUD to whichever external monitor the mouse happened to
/// be on.
@MainActor
enum NotchGeometryProvider {
    /// - `NSScreen.screens[0]` is the primary display (the one owning the menu
    ///   bar), so scanning in order prefers it whenever it qualifies.
    static func current() -> DisplayGeometry {
        let screens = NSScreen.screens
        let notched = screens.first { notchMetrics(for: $0) != nil }

        guard let screen = notched ?? screens.first else { return .fallback }

        if let metrics = notchMetrics(for: screen),
           let left = screen.auxiliaryTopLeftArea {
            return DisplayGeometry(
                presence: .physical,
                metrics: metrics,
                centerX: left.maxX + metrics.notchWidth / 2,
                topY: screen.frame.maxY,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }

        return DisplayGeometry(
            presence: .none,
            metrics: .fallback,
            centerX: screen.frame.midX,
            // Sit below the menu bar rather than over it.
            topY: screen.visibleFrame.maxY,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }

    /// Measures the hardware notch, or `nil` if this display doesn't have one.
    static func notchMetrics(for screen: NSScreen) -> NotchMetrics? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.width > 0, right.width > 0
        else { return nil }

        let width = right.minX - left.maxX
        let height = screen.frame.maxY - left.minY
        guard width > 0, height > 0 else { return nil }

        return NotchMetrics(notchWidth: width, notchHeight: height)
    }
}
