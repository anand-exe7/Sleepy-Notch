import AppKit

/// The app's icon, drawn in code because the app has no bundle to carry an
/// icon file: a black rounded square — the notch's own black — with the
/// moon from the Settings sidebar. Without it the Dock shows the generic
/// "exec" icon while Settings is open.
@MainActor
enum AppIcon {
    /// Pixels on a side of the one bitmap the icon is kept in. Sharp for the
    /// biggest Dock size on a Retina screen; about 1 MB.
    private static let pixels = 512

    /// Drawn once into a fixed 8-bit bitmap. (An image made from a drawing
    /// closure is re-rendered by the system at 2048 px in 16-bit colour, twice,
    /// which cost about 80 MB of memory for an icon seen only in the Dock.)
    static func make() -> NSImage {
        let side = CGFloat(pixels)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return NSImage(size: NSSize(width: side, height: side))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The artwork is laid out on a 1024-point canvas.
        let transform = NSAffineTransform()
        transform.scale(by: side / 1024)
        transform.concat()
        draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private static func draw(in canvas: NSRect) {
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
    }
}
