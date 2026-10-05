import AppKit

/// Album art by track, so coming back to a song doesn't fetch it again over
/// AppleScript or the network.
@MainActor
final class ArtworkCache {
    private let cache = NSCache<NSString, NSImage>()

    func image(for track: TrackInfo) -> NSImage? {
        cache.object(forKey: key(for: track))
    }

    func store(_ image: NSImage, for track: TrackInfo) {
        cache.setObject(image, forKey: key(for: track))
    }

    private func key(for track: TrackInfo) -> NSString {
        "\(track.artist)-\(track.title)" as NSString
    }
}
