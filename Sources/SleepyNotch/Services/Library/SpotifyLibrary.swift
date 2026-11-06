import Foundation

/// Spotify's library through its web API, signed in by `SpotifyAuth`.
/// Every call is one request made when a button is pressed or the card is
/// opened; nothing runs in between.
@MainActor
final class SpotifyLibrary: LibraryBackend {
    private let auth: SpotifyAuth
    private var userID: String?

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func isLiked(_ track: TrackInfo) async throws -> Bool {
        let id = try trackID(track)
        let (data, _) = try await request("GET", "/v1/me/tracks/contains", query: [("ids", id)])
        let flags = (try? JSONSerialization.jsonObject(with: data)) as? [Bool]
        return flags?.first ?? false
    }

    func setLiked(_ liked: Bool, track: TrackInfo) async throws {
        let id = try trackID(track)
        _ = try await request(liked ? "PUT" : "DELETE", "/v1/me/tracks", query: [("ids", id)])
    }

    func playlists() async throws -> [LibraryPlaylist] {
        let me = try await currentUserID()
        var found: [LibraryPlaylist] = []
        var path: String? = "/v1/me/playlists"
        var query: [(String, String)] = [("limit", "50")]
        // A few pages is plenty for a menu.
        for _ in 0..<4 {
            guard let current = path else { break }
            let (data, _) = try await request("GET", current, query: query)
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { break }
            for item in (json["items"] as? [[String: Any]]) ?? [] {
                guard let id = item["id"] as? String, let name = item["name"] as? String else { continue }
                let owner = (item["owner"] as? [String: Any])?["id"] as? String
                // Only lists a song can actually be added to.
                if owner == me || (item["collaborative"] as? Bool) == true {
                    found.append(LibraryPlaylist(id: id, name: name))
                }
            }
            // `next` is a full URL; keep its path and query.
            if let next = json["next"] as? String, let url = URL(string: next) {
                path = url.path
                query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .map { ($0.name, $0.value ?? "") } ?? []
            } else {
                path = nil
            }
        }
        return found
    }

    func add(_ track: TrackInfo, to playlist: LibraryPlaylist) async throws {
        _ = try trackID(track)
        let body = try JSONSerialization.data(withJSONObject: ["uris": [track.uri ?? ""]])
        _ = try await request("POST", "/v1/playlists/\(playlist.id)/tracks", body: body)
    }

    // MARK: - Requests

    private func trackID(_ track: TrackInfo) throws -> String {
        guard let uri = track.uri, uri.hasPrefix("spotify:track:") else { throw LibraryError.notASong }
        return String(uri.dropFirst("spotify:track:".count))
    }

    private func currentUserID() async throws -> String {
        if let userID { return userID }
        let (data, _) = try await request("GET", "/v1/me")
        guard let id = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["id"] as? String else {
            throw LibraryError(message: "Couldn't read your Spotify account.")
        }
        userID = id
        return id
    }

    private func request(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        body: Data? = nil
    ) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://api.spotify.com")!
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.validToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
            throw LibraryError(message: status == 403
                ? "Spotify refused this: \(message ?? "check the app's permissions")."
                : message ?? "Spotify returned \(status).")
        }
        return (data, status)
    }
}
