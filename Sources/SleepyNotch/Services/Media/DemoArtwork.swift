import AppKit

/// Generated album covers for demo mode, so artwork animations can be tried
/// without real music. Each palette draws a two-tone gradient with soft
/// shapes; nothing is copied from real album art.
enum DemoArtwork {
    struct Palette {
        let top: NSColor
        let bottom: NSColor
        let accent: NSColor
    }

    static let palettes: [Palette] = [
        Palette(top: rgb(0.95, 0.20, 0.25), bottom: rgb(0.12, 0.02, 0.08), accent: rgb(1.0, 0.85, 0.35)),
        Palette(top: rgb(0.55, 0.25, 0.95), bottom: rgb(0.95, 0.35, 0.65), accent: rgb(0.35, 0.95, 1.0)),
        Palette(top: rgb(1.0, 0.78, 0.25), bottom: rgb(0.75, 0.30, 0.05), accent: rgb(1.0, 1.0, 0.9)),
        Palette(top: rgb(0.10, 0.75, 0.70), bottom: rgb(0.05, 0.15, 0.35), accent: rgb(0.70, 1.0, 0.55)),
    ]

    /// A 300×300 cover for `index`, drawn once into a bitmap.
    static func cover(_ index: Int) -> NSImage {
        let palette = palettes[index % palettes.count]
        let side = 300
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return NSImage(size: NSSize(width: side, height: side))
        }

        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSGradient(starting: palette.top, ending: palette.bottom)?.draw(in: bounds, angle: -70)

        // A large soft disc and a ring, offset differently per cover.
        let shift = CGFloat(index % 3) * 40
        palette.accent.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: 40 + shift, y: 110 - shift / 2, width: 170, height: 170)).fill()

        palette.accent.withAlphaComponent(0.8).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 150 - shift, y: 40 + shift / 2, width: 110, height: 110))
        ring.lineWidth = 6
        ring.stroke()

        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: 46)).fill()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
    }
}
