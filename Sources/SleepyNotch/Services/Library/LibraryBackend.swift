import Foundation

struct LibraryPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Why liking a song or adding it to a playlist didn't work, in words the
/// card can show.
struct LibraryError: Error {
    let message: String
}

/// What the like and playlist buttons need from a music service. One
/// backend per source: Apple Music by scripting, and an in-memory one for
/// Demo Mode.
@MainActor
protocol LibraryBackend {
    func isLiked(_ track: TrackInfo) async throws -> Bool
    func setLiked(_ liked: Bool, track: TrackInfo) async throws
    func playlists() async throws -> [LibraryPlaylist]
    func add(_ track: TrackInfo, to playlist: LibraryPlaylist) async throws
}
