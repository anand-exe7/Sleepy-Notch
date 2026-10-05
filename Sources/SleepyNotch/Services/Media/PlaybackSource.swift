import AppKit

/// One place music can come from — Apple Music, Spotify, or the built-in
/// demo — behind the same few commands, so `PlaybackCoordinator` never has
/// to ask which one it's talking to. Adding a player means adding a type
/// that conforms to this.
@MainActor
protocol PlaybackSource: AnyObject {
    var kind: MusicSource { get }

    /// Called whenever the source reports a new track or state on its own:
    /// a notification from the app, or the demo changing songs.
    var onUpdate: ((TrackInfo) -> Void)? { get set }

    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    /// Moves to `seconds` into the current track.
    func seek(toSeconds seconds: Double) async throws

    /// What the source is doing right now, used to pick one at launch.
    /// `nil` when it can't say — not running, or no Automation access.
    func currentStatus() async -> SourceStatus?

    /// Artwork for the current track, fetched however this source provides
    /// it. `nil` if there is none.
    func artwork() async -> NSImage?
}

/// What a single music app reports about itself at launch.
struct SourceStatus {
    let source: MusicSource
    /// "playing", "paused" or "stopped", lowercased.
    let state: String
    let track: TrackInfo?

    var isPlaying: Bool { state == "playing" }
    var hasTrack: Bool { track != nil }
}
