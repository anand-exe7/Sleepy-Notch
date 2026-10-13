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

    /// Spotify reports a track's `duration` in **milliseconds**; Apple Music
    /// uses seconds.
    func normalizedDuration(_ raw: Double) -> Double {
        self == .spotify ? raw / 1000.0 : raw
    }

    /// Playback position in seconds. Both apps document `player position`
    /// in seconds, but a value that couldn't possibly fit in the track can
    /// only be milliseconds, so it's scaled down rather than pinning the
    /// timeline to the end.
    func normalizedPosition(_ raw: Double, duration: Double) -> Double {
        if duration > 0, raw > duration + 5 { return raw / 1000.0 }
        return raw
    }
}
