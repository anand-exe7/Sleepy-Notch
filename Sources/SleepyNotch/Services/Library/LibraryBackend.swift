import Foundation

struct LibraryPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Why liking a song or adding it to a playlist didn't work, in words the
/// card can show.
struct LibraryError: Error {
    let message: String

    static let notSignedIn = LibraryError(message: "Connect Spotify in Settings first.")
    static let notASong = LibraryError(message: "This isn't a song, so it can't be saved.")
}

/// What the like and playlist buttons need from a music service. One
/// backend per source: Apple Music by scripting, Spotify through its web
/// API, and an in-memory one for Demo Mode.
@MainActor
protocol LibraryBackend {
    func isLiked(_ track: TrackInfo) async throws -> Bool
    func setLiked(_ liked: Bool, track: TrackInfo) async throws
    func playlists() async throws -> [LibraryPlaylist]
    func add(_ track: TrackInfo, to playlist: LibraryPlaylist) async throws
}
