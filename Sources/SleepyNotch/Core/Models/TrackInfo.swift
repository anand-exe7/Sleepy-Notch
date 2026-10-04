import Foundation
import AppKit

public enum MusicSource: String, CaseIterable, Sendable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case demo = "Demo Mode"
    
    public var iconName: String {
        switch self {
        case .appleMusic: return "music.note"
        case .spotify: return "antenna.radiowaves.left.and.right"
        case .demo: return "sparkles"
        }
    }

    /// Spotify's AppleScript dictionary reports both `duration` and
    /// `player position` in **milliseconds**; Apple Music uses seconds.
    ///
    /// The two values always arrive in the same response, so they are always
    /// the same unit — reading one as ms and the other as s is a bug that
    /// shows up as a scrubber permanently pinned to the end of the track.
    public var usesMillisecondTime: Bool {
        self == .spotify
    }

    /// Converts a raw AppleScript time value into seconds.
    public func normalizedTime(_ raw: Double) -> Double {
        usesMillisecondTime ? raw / 1000.0 : raw
    }
}

/// Not `Sendable`: `artworkImage` is an `NSImage`, which isn't thread-safe.
/// Keep `TrackInfo` on the main actor and hand only plain values across tasks.
public struct TrackInfo: Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double // in seconds
    public var position: Double // in seconds
    public var isPlaying: Bool
    public var source: MusicSource
    public var artworkImage: NSImage?
    public var lastUpdated: Date
    
    public init(
        title: String = "No Track Playing",
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
    
    public var currentPosition: Double {
        position(at: Date())
    }

    public var progressRatio: Double {
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
    
    public static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.source == rhs.source &&
        abs(lhs.position - rhs.position) < 1.0 &&
        lhs.duration == rhs.duration
    }
}
