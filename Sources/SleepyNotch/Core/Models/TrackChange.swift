import AppKit

/// The parts of a track a song-change peek shows, frozen at the moment of
/// the change so the old cover can animate out.
struct TrackSnapshot: Equatable {
    let key: String
    let title: String
    let artist: String
    let source: MusicSource
    let artwork: NSImage?

    init(_ track: TrackInfo) {
        key = track.identityKey
        title = track.title
        artist = track.artist
        source = track.source
        artwork = track.artworkImage
    }

    var isPlaceholder: Bool {
        title == TrackInfo.placeholderTitle && source == .demo
    }
}

struct TrackChange: Equatable {
    let previous: TrackSnapshot
    let current: TrackSnapshot
}
