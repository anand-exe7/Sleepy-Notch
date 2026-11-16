import AppKit
import ImageIO
import QuickLookThumbnailing

/// Previews for shelf items and dragged files, made once per file and size
/// and cached. Pictures are read straight with ImageIO (fast, and works
/// for files Quick Look hasn't indexed yet); everything else goes through
/// Quick Look. The Finder icon stands in when neither can, and that
/// stand-in is never cached, so a file that was still being written when
/// first asked gets its real preview next time.
@MainActor
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        // Keyed by size too: the drop zone, the shelf and its tiles ask for
        // different sizes, and a small one blown up looks soft.
        let key = "\(Int(side))|\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let pixels = side * 2
        var made = await imageThumbnail(url, pixels: pixels)
        if made == nil { made = await quickLook(url, side: side) }
        if let image = made {
            cache.setObject(image, forKey: key)
            return image
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// A picture's own thumbnail, decoded off the main thread.
    private static func imageThumbnail(_ url: URL, pixels: CGFloat) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: pixels,
                  ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        }.value
    }

    private static func quickLook(_ url: URL, side: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: 2,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
