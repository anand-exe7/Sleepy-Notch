import AppKit

/// Generated album covers for demo mode, so artwork animations can be tried
/// without real music.
///
/// Designed like real minimalist record sleeves: one flat, muted colour, a
/// single bold shape, and the album name set small in the system font. No
/// gradients or glow. Nothing is copied from real album art.
enum DemoArtwork {
    private enum Shape {
        /// A large disc, off-centre.
        case disc
        /// A half disc rising from the bottom edge, like a setting sun.
        case horizon
        /// A thick ring.
        case ring
        /// Three horizontal bars of decreasing width.
        case bars
    }

    private struct Design {
        let background: NSColor
        let ink: NSColor
        let shape: Shape
        let title: String
    }

    private static let designs: [Design] = [
        Design(background: hex(0xE9E4DA), ink: hex(0x1C1C1E), shape: .disc, title: "STARBOY"),
        Design(background: hex(0x1F2638), ink: hex(0xE6D8BD), shape: .horizon, title: "HURRY UP, WE'RE DREAMING"),
        Design(background: hex(0xB4553B), ink: hex(0xF2E8D5), shape: .ring, title: "RANDOM ACCESS MEMORIES"),
        Design(background: hex(0x2F4636), ink: hex(0xD2DCC2), shape: .bars, title: "ORACULAR SPECTACULAR"),
    ]

    /// A 300×300 cover for `index`, drawn once into a bitmap.
    static func cover(_ index: Int) -> NSImage {
        let design = designs[index % designs.count]
        let side: CGFloat = 300
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(side),
            pixelsHigh: Int(side),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: Int(side) * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return NSImage(size: NSSize(width: side, height: side))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        design.background.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()

        design.ink.setFill()
        design.ink.setStroke()
        switch design.shape {
        case .disc:
            NSBezierPath(ovalIn: NSRect(x: 112, y: 58, width: 156, height: 156)).fill()
        case .horizon:
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 150, y: 0), radius: 112, startAngle: 0, endAngle: 180)
            sun.close()
            sun.fill()
        case .ring:
            let ring = NSBezierPath(ovalIn: NSRect(x: 70, y: 52, width: 160, height: 160))
            ring.lineWidth = 26
            ring.stroke()
        case .bars:
            for (row, width) in [200.0, 150.0, 100.0].enumerated() {
                NSRect(x: 32, y: 60 + CGFloat(row) * 44, width: width, height: 22).fill()
            }
        }

        // Album name, small and tracked out, top-left — the way a sleeve
        // carries its title.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: design.ink,
            .kern: 2.4,
        ]
        NSAttributedString(string: design.title, attributes: attributes)
            .draw(in: NSRect(x: 30, y: side - 72, width: side - 60, height: 44))

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            deviceRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
