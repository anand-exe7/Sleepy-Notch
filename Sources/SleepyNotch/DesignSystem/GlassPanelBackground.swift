import AppKit
import SwiftUI

/// Apple's own glass behind a SwiftUI view: Liquid Glass on macOS 26, the
/// HUD's frosted material before it. It blurs whatever is behind the
/// window (the lock screen's wallpaper, say), like the system's own
/// panels, and keeps its corners at `cornerRadius` while it resizes.
struct GlassPanelBackground: NSViewRepresentable {
    let cornerRadius: CGFloat
    /// A dark tint, so white text stays readable over a light wallpaper.
    var tint: CGFloat = 0.28

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = NSColor.black.withAlphaComponent(tint)
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        let frosted = NSVisualEffectView()
        frosted.material = .hudWindow
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.appearance = NSAppearance(named: .darkAqua)
        frosted.wantsLayer = true
        frosted.layer?.cornerRadius = cornerRadius
        frosted.layer?.cornerCurve = .continuous
        frosted.layer?.masksToBounds = true
        return frosted
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.tintColor = NSColor.black.withAlphaComponent(tint)
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }
}
