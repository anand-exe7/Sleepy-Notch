import AppKit

/// The app's icon, drawn in code because the app has no bundle to carry an
/// icon file: a black rounded square — the notch's own black — with the
/// moon from the Settings sidebar. Without it the Dock shows the generic
/// "exec" icon while Settings is open.
@MainActor
enum AppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        return NSImage(size: size, flipped: false) { canvas in
            // Apple's icon grid: an 824pt body centred on the 1024pt canvas,
            // leaving room for the Dock's own shadow.
            let body = canvas.insetBy(dx: 100, dy: 100)
            let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

            NSGradient(
                starting: NSColor(white: 0.16, alpha: 1),
                ending: NSColor(white: 0.02, alpha: 1)
            )?.draw(in: shape, angle: -90)

            NSColor(white: 1, alpha: 0.14).setStroke()
            shape.lineWidth = 4
            shape.stroke()

            let configuration = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let moon = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let glyph = moon.size
                moon.draw(in: NSRect(
                    x: body.midX - glyph.width / 2,
                    y: body.midY - glyph.height / 2,
                    width: glyph.width,
                    height: glyph.height
                ))
            }
            return true
        }
    }
}
