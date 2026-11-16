import AppKit

/// The full-screen art's own state: whether it has arrived (so its pieces
/// rise in after the window is up), Playing Next open or not, the volume
/// and the animated cover's address.
@MainActor
final class LockScreenArtModel: ObservableObject {
    @Published var isShown = false
    @Published var showsQueue = false
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var motionURL: URL?
    /// The cover at full-screen size (the player's own is 600-1000 px,
    /// which looked soft stretched across the screen). Dropped on close.
    @Published private(set) var largeArtwork: NSImage?
    /// Bumped per song, so a slow lookup for the last one is dropped.
    private var generation = 0

    /// Everything read once, when the art opens or the song changes.
    func load(for track: TrackInfo, upNext: UpNextService) {
        volume = SystemLevels.volume() ?? volume
        upNext.refresh(for: track)
        motionURL = nil
        largeArtwork = nil
        generation += 1
        let ticket = generation
        Task { [weak self] in
            let image = await CatalogueArtwork.image(title: track.title, artist: track.artist, pixels: 3000)
            guard let self, ticket == self.generation else { return }
            self.largeArtwork = image
        }
        Task { [weak self] in
            let url = await MotionArtworkService.shared.videoURL(for: track)
            guard let self, ticket == self.generation else { return }
            self.motionURL = url
        }
    }

    func setVolume(_ level: Double) {
        volume = level
        _ = SystemLevels.setVolume(level)
    }

    func reset() {
        generation += 1
        isShown = false
        showsQueue = false
        motionURL = nil
        largeArtwork = nil
    }
}
