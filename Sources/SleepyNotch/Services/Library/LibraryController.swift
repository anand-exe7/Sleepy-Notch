import Foundation

/// Liking the current song and adding it to a playlist, in whichever
/// service it's playing from. The card's two buttons read and drive this.
///
/// Event-driven: the like state is asked once when the card opens or the
/// song changes, and playlists are fetched once and kept for ten minutes.
/// Nothing runs between button presses.
@MainActor
final class LibraryController: ObservableObject {
    /// A brief answer shown on the buttons after pressing one.
    enum Flash: Equatable {
        case liked(Bool)
        case added(String)
        case problem(String)
    }

    @Published private(set) var isLiked: Bool?
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var isLoadingPlaylists = false
    @Published private(set) var flash: Flash?

    private let media: PlaybackCoordinator
    private let apple = AppleMusicLibrary()
    private let demo = DemoLibrary()

    private var playlistsLoaded: (source: MusicSource, at: Date)?
    private var generation = 0
    private var flashWork: DispatchWorkItem?
    private static let playlistsLifetime: TimeInterval = 600
    private static let flashTime: TimeInterval = 1.6

    init(media: PlaybackCoordinator) {
        self.media = media
    }

    // MARK: - What's possible now

    private var backend: LibraryBackend? {
        switch media.currentTrack.source {
        case .appleMusic: return apple
        case .spotify: return nil
        case .demo: return demo
        }
    }

    /// Whether the buttons are shown: Apple Music, and Demo Mode. Spotify
    /// has no way to like a song or fill a playlist without its web API and a
    /// sign-in, so it gets neither button.
    var isSupported: Bool {
        media.currentTrack.source != .spotify
    }

    /// Whether the buttons do anything right now: not with nothing playing.
    var canAct: Bool {
        isSupported && !media.currentTrack.isPlaceholder
    }

    // MARK: - Reading

    /// Asks whether the current song is liked, and loads the playlists if
    /// they're missing or old. Called when the card opens or the song changes.
    func refresh() {
        generation += 1
        let current = generation
        isLiked = nil
        let track = media.currentTrack
        guard canAct, let backend else { return }
        Task {
            let liked = try? await backend.isLiked(track)
            guard current == generation else { return }
            isLiked = liked
            await loadPlaylistsIfStale(backend, source: track.source)
        }
    }

    private func loadPlaylistsIfStale(_ backend: LibraryBackend, source: MusicSource) async {
        if let loaded = playlistsLoaded, loaded.source == source,
           Date().timeIntervalSince(loaded.at) < Self.playlistsLifetime { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        guard let found = try? await backend.playlists() else { return }
        playlists = found
        playlistsLoaded = (source, Date())
    }

    // MARK: - Pressing

    func toggleLike() {
        guard canAct else { return }
        guard let backend else { return }
        let track = media.currentTrack
        let target = !(isLiked ?? false)
        isLiked = target
        Task {
            do {
                try await backend.setLiked(target, track: track)
                show(.liked(target))
            } catch {
                if media.currentTrack.identityKey == track.identityKey { isLiked = !target }
                show(.problem(Self.message(for: error)))
            }
        }
    }

    func add(to playlist: LibraryPlaylist) {
        guard canAct else { return }
        guard let backend else { return }
        let track = media.currentTrack
        Task {
            do {
                try await backend.add(track, to: playlist)
                show(.added(playlist.name))
            } catch {
                show(.problem(Self.message(for: error)))
            }
        }
    }

    /// Opens the playlists' own list again next time, e.g. after the user
    /// made one in the app.
    func forgetPlaylists() {
        playlistsLoaded = nil
    }

    // MARK: - Helpers

    private func show(_ flash: Flash) {
        flashWork?.cancel()
        self.flash = flash
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashTime, execute: work)
    }

    private static func message(for error: Error) -> String {
        (error as? LibraryError)?.message ?? error.localizedDescription
    }
}
