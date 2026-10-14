import AppKit
import CoreGraphics

/// Whether Mission Control is open. macOS has no API for it, but while it's
/// up the window manager puts full-width windows (the Spaces bar, the
/// overlay) at the Dock's levels, which aren't there otherwise. The Dock's
/// own full-screen window isn't used: it also appears outside Mission
/// Control. Reading the window list needs no permission
/// (only window titles do). One read per call; callers ask only at the
/// moments it matters.
enum MissionControl {
    static func isOpen(on screen: NSScreen?) -> Bool {
        guard let screen,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let size = screen.frame.size
        return windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "WindowManager",
                  let layer = window[kCGWindowLayer as String] as? Int,
                  (14...20).contains(layer),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat
            else { return false }
            return width >= size.width && height >= 60
        }
    }
}
