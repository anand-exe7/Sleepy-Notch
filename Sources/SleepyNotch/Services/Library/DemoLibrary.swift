import Foundation

/// Demo Mode's library: remembered in memory only, so the buttons can be
/// tried without touching a real account.
@MainActor
final class DemoLibrary: LibraryBackend {
    private var liked: Set<String> = []

    func isLiked(_ track: TrackInfo) async throws -> Bool {
        liked.contains(track.identityKey)
    }

    func setLiked(_ liked: Bool, track: TrackInfo) async throws {
        if liked { self.liked.insert(track.identityKey) } else { self.liked.remove(track.identityKey) }
    }

    func playlists() async throws -> [LibraryPlaylist] {
        ["Chill", "Workout", "Focus"].map { LibraryPlaylist(id: $0, name: $0) }
    }

    func add(_ track: TrackInfo, to playlist: LibraryPlaylist) async throws {}
}
