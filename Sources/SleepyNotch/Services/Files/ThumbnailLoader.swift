import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails for shelf items, made once per file and cached.
/// Falls back to the Finder icon for files Quick Look can't preview.
@MainActor
enum ThumbnailLoader {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: 2,
            representationTypes: .all
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
