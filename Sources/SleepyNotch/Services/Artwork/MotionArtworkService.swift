import Foundation
import Security

/// Apple Music's animated album covers ("motion artwork"), for the lock
/// screen's full-screen art.
///
/// Apple only serves them through the Apple Music API, which needs a
/// MusicKit developer token made with the user's own Apple Developer
/// account. With none saved, this does nothing and the still cover is used.
/// The token lives in the Keychain. Per album: one search and one lookup,
/// remembered for the session (misses too), and only when the full-screen
/// art opens.
@MainActor
final class MotionArtworkService: ObservableObject {
    static let shared = MotionArtworkService()

    @Published private(set) var hasToken = false
    /// What's typed into Settings, before it's saved.
    @Published var tokenDraft = ""
    /// The last lookup's trouble, for Settings.
    @Published private(set) var problem: String?

    private var cache: [String: URL?] = [:]

    private init() {
        hasToken = Self.readToken() != nil
    }

    // MARK: - Token

    func saveDraft() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        Self.writeToken(token)
        tokenDraft = ""
        hasToken = true
        problem = nil
        cache = [:]
    }

    func removeToken() {
        Self.deleteToken()
        hasToken = false
        cache = [:]
    }

    // MARK: - Lookup

    /// The looping video for this song's album, or nil (no token, not in
    /// the catalogue, or the album has no motion cover).
    func videoURL(for track: TrackInfo) async -> URL? {
        guard !track.isPlaceholder, let token = Self.readToken() else { return nil }
        let key = "\(track.artist.lowercased())|\(track.album.lowercased())|\(track.title.lowercased())"
        if let cached = cache[key] { return cached }
        let url = await Self.lookUp(track, token: token, storefront: Self.storefront)
        cache[key] = url
        return url
    }

    private static var storefront: String {
        let region: String?
        if #available(macOS 13, *) {
            region = Locale.current.region?.identifier
        } else {
            region = Locale.current.regionCode
        }
        return (region ?? "us").lowercased()
    }

    private nonisolated static func lookUp(_ track: TrackInfo, token: String, storefront: String) async -> URL? {
        // The album: searched by its name and artist (or the song's, for a
        // single).
        let term = [track.album.isEmpty ? track.title : track.album, track.artist].joined(separator: " ")
        var search = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/search")
        search?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "types", value: "albums"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let searchURL = search?.url,
              let found: SearchResponse = await get(searchURL, token: token),
              let albums = found.results.albums?.data, !albums.isEmpty
        else { return nil }
        let wanted = track.album.lowercased()
        let artist = track.artist.lowercased()
        let album = albums.first {
            ($0.attributes?.name?.lowercased()).map { $0 == wanted || $0.hasPrefix(wanted) || wanted.hasPrefix($0) } == true
                && ($0.attributes?.artistName?.lowercased()).map { $0.contains(artist) || artist.contains($0) } == true
        } ?? albums[0]

        guard let detailURL = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/albums/\(album.id)?extend=editorialVideo"),
              let detail: AlbumResponse = await get(detailURL, token: token),
              let video = detail.data.first?.attributes?.editorialVideo
        else { return nil }
        // Square first: it crops best to any screen.
        let candidates = [video.motionDetailSquare, video.motionSquareVideo1x1, video.motionDetailTall, video.motionTallVideo3x4]
        return candidates.compactMap { $0?.video }.compactMap(URL.init(string:)).first
    }

    private nonisolated static func get<T: Decodable>(_ url: URL, token: String) async -> T? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            await MainActor.run {
                MotionArtworkService.shared.problem = status == 401 || status == 403
                    ? "Apple Music didn't accept the token (it may have expired)."
                    : "Apple Music answered \(status)."
            }
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - API shapes

    private struct SearchResponse: Decodable {
        struct Results: Decodable { let albums: AlbumList? }
        struct AlbumList: Decodable { let data: [Album] }
        let results: Results
    }

    private struct AlbumResponse: Decodable {
        let data: [Album]
    }

    private struct Album: Decodable {
        struct Attributes: Decodable {
            let name: String?
            let artistName: String?
            let editorialVideo: EditorialVideo?
        }
        let id: String
        let attributes: Attributes?
    }

    private struct EditorialVideo: Decodable {
        struct Asset: Decodable { let video: String? }
        let motionDetailSquare: Asset?
        let motionSquareVideo1x1: Asset?
        let motionDetailTall: Asset?
        let motionTallVideo3x4: Asset?
    }

    // MARK: - Keychain

    nonisolated private static let service = "Sleepy Notch"
    nonisolated private static let account = "musickit-developer-token"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private nonisolated static func readToken() -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String) {
        deleteToken()
        var add = query()
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deleteToken() {
        SecItemDelete(query() as CFDictionary)
    }
}
