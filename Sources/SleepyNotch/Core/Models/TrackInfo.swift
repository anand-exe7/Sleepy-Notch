import Foundation
import AppKit

/// Not `Sendable`: `artworkImage` is an `NSImage`, which isn't thread-safe.
/// Keep `TrackInfo` on the main actor and hand only plain values across tasks.
struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double // in seconds
    var position: Double // in seconds
    var isPlaying: Bool
    var source: MusicSource
    var artworkImage: NSImage?
    var lastUpdated: Date
    
    /// Title of the empty "nothing is playing" card.
    static let placeholderTitle = "No Track Playing"

    init(
        title: String = TrackInfo.placeholderTitle,
        artist: String = "Enjoy the silence",
        album: String = "",
        duration: Double = 200,
        position: Double = 0,
        isPlaying: Bool = false,
        source: MusicSource = .demo,
        artworkImage: NSImage? = nil,
        lastUpdated: Date = Date()
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.source = source
        self.artworkImage = artworkImage
        self.lastUpdated = lastUpdated
    }
    
    /// Identifies the song, not its playback state: changes only when a
    /// different track starts. Artwork transitions and song-change peeks key
    /// off this, so play/pause and seeks never trigger them.
    var identityKey: String {
        "\(source.rawValue)|\(title)|\(artist)"
    }

    /// The empty card shown when nothing is playing anywhere.
    var isPlaceholder: Bool {
        title == Self.placeholderTitle && source == .demo
    }

    var currentPosition: Double {
        position(at: Date())
    }

    var progressRatio: Double {
        progressRatio(at: Date())
    }

    /// Playback position at `date`, extrapolated from the last report.
    func position(at date: Date) -> Double {
        if !isPlaying { return min(position, duration) }
        let elapsed = date.timeIntervalSince(lastUpdated)
        return min(position + elapsed, duration)
    }

    func progressRatio(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(position(at: date) / duration, 0), 1)
    }
    
    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.source == rhs.source &&
        abs(lhs.position - rhs.position) < 1.0 &&
        lhs.duration == rhs.duration
    }
}
