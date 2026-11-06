import Foundation

/// Apple Music's library, by scripting: the heart is the track's
/// `favorited` flag and a playlist gets a copy of the track. Only songs in
/// your library can be added to a playlist; Music refuses the rest.
@MainActor
struct AppleMusicLibrary: LibraryBackend {
    private static let separator = "|||"

    func isLiked(_ track: TrackInfo) async throws -> Bool {
        let text = try await run("tell application \"Music\" to return (favorited of current track) as string")
        return text == "true"
    }

    func setLiked(_ liked: Bool, track: TrackInfo) async throws {
        _ = try await run("tell application \"Music\" to set favorited of current track to \(liked)")
    }

    func playlists() async throws -> [LibraryPlaylist] {
        // Plain playlists only: not smart ones, and not Music's built-in
        // lists, none of which a song can be added to.
        let script = """
        set theNames to {}
        tell application "Music"
            repeat with p in (every user playlist)
                try
                    if (smart of p) is false and ((special kind of p) as string) is "none" then set end of theNames to (name of p)
                end try
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(Self.separator)"
        return theNames as text
        """
        let text = try await run(script)
        return text.components(separatedBy: Self.separator)
            .filter { !$0.isEmpty }
            .map { LibraryPlaylist(id: $0, name: $0) }
    }

    func add(_ track: TrackInfo, to playlist: LibraryPlaylist) async throws {
        let name = playlist.name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await run("tell application \"Music\" to duplicate current track to playlist \"\(name)\"")
    }

    private func run(_ script: String) async throws -> String {
        do {
            return try await AppleScriptRunner.shared.run(script).text ?? ""
        } catch let failure as AppleScriptFailure {
            throw LibraryError(message: failure.shortDescription)
        }
    }
}
