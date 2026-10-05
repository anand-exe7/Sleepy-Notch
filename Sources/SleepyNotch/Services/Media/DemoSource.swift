import AppKit

/// A built-in playlist for trying the HUD without Music or Spotify running.
///
/// It only starts by hand (menu, `d`, or the Feature Lab) and always starts
/// paused, so it never animates on its own. Commands succeed instantly:
/// play/pause and seek are already shown by the coordinator's optimistic
/// update, so there's nothing more to do for them here.
@MainActor
final class DemoSource: PlaybackSource {
    let kind = MusicSource.demo
    var onUpdate: ((TrackInfo) -> Void)?

    private var index = 0
    /// Mirrors the play state shown on screen, so changing songs keeps it.
    private var isPlaying = false

    private let tracks: [TrackInfo] = [
        TrackInfo(
            title: "Starboy",
            artist: "The Weeknd, Daft Punk",
            album: "Starboy",
            duration: 230,
            position: 45,
            source: .demo,
            artworkImage: DemoArtwork.cover(0)
        ),
        TrackInfo(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243,
            position: 80,
            source: .demo,
            artworkImage: DemoArtwork.cover(1)
        ),
        TrackInfo(
            title: "Get Lucky",
            artist: "Daft Punk ft. Pharrell Williams",
            album: "Random Access Memories",
            duration: 248,
            position: 112,
            source: .demo,
            artworkImage: DemoArtwork.cover(2)
        ),
        TrackInfo(
            title: "Electric Feel",
            artist: "MGMT",
            album: "Oracular Spectacular",
            duration: 229,
            position: 30,
            source: .demo,
            artworkImage: DemoArtwork.cover(3)
        ),
    ]

    /// Shows the demo, paused — on the next song if `advancing`.
    func start(advancing: Bool) {
        if advancing { index = (index + 1) % tracks.count }
        isPlaying = false
        emit()
    }

    /// Moves to the next song, keeping the current play state.
    func showNext() {
        index = (index + 1) % tracks.count
        emit()
    }

    func togglePlayPause() async throws {
        isPlaying.toggle()
    }

    func nextTrack() async throws {
        showNext()
    }

    func previousTrack() async throws {
        index = (index - 1 + tracks.count) % tracks.count
        emit()
    }

    func seek(toSeconds seconds: Double) async throws {}

    func currentStatus() async -> SourceStatus? { nil }

    func artwork() async -> NSImage? {
        tracks[index].artworkImage
    }

    private func emit() {
        var track = tracks[index]
        track.isPlaying = isPlaying
        track.lastUpdated = Date()
        onUpdate?(track)
    }
}
