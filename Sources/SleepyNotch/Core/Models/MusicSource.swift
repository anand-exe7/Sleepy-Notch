import Foundation

/// Where the current track comes from.
enum MusicSource: String, CaseIterable, Sendable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case demo = "Demo Mode"
    
    var iconName: String {
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
    var usesMillisecondTime: Bool {
        self == .spotify
    }

    /// Converts a raw AppleScript time value into seconds.
    func normalizedTime(_ raw: Double) -> Double {
        usesMillisecondTime ? raw / 1000.0 : raw
    }
}
