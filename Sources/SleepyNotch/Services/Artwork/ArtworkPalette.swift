import AppKit

/// Picks a tint colour from album art, for the optional "tint controls with
/// album colour" setting.
///
/// A plain average turns most covers muddy grey, so pixels are weighted by
/// how vivid they are (saturation × brightness) and the result is lifted to
/// a brightness that reads on black. Computed once per image and cached; it
/// draws the cover into a 12×12 bitmap, so it's cheap even the first time.
@MainActor
enum ArtworkPalette {
    private static let cache = NSCache<NSImage, NSColor>()
    private static let sampleSize = 12

    static func tint(for image: NSImage) -> NSColor? {
        if let cached = cache.object(forKey: image) { return cached }
        guard let color = computeTint(for: image) else { return nil }
        cache.setObject(color, forKey: image)
        return color
    }

    private static func computeTint(for image: NSImage) -> NSColor? {
        let side = sampleSize
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, total: CGFloat = 0
        for x in 0..<side {
            for y in 0..<side {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let weight = pixel.saturationComponent * pixel.brightnessComponent + 0.02
                red += pixel.redComponent * weight
                green += pixel.greenComponent * weight
                blue += pixel.blueComponent * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }

        let average = NSColor(deviceRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        return NSColor(
            deviceHue: average.hueComponent,
            saturation: min(1, average.saturationComponent * 1.25 + 0.1),
            brightness: max(0.8, average.brightnessComponent),
            alpha: 1
        )
    }
}
