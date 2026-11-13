import AppKit

/// Album art from Apple's public catalogue search (no account or key), by
/// title and artist, at the size asked for: the search hands out a 100 px
/// thumbnail whose address serves any size up to the original.
///
/// Used where the player gives no art (songs streamed in Apple Music) and
/// where the player's art is too small (the full-screen lock screen).
enum CatalogueArtwork {
    /// One search request and one image download; nil when no song with
    /// this title and artist is found.
    static func image(title: String, artist: String, pixels: Int) async -> NSImage? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Search.self, from: data)
        else { return nil }
        let wantedTitle = title.lowercased()
        let wantedArtist = artist.lowercased()
        let sameArtist = response.results.filter {
            guard $0.artworkUrl100 != nil, let found = $0.artistName?.lowercased(), !found.isEmpty else { return false }
            return found.contains(wantedArtist) || wantedArtist.contains(found)
        }
        guard let match = sameArtist.first(where: { $0.trackName?.lowercased() == wantedTitle }) ?? sameArtist.first,
              let thumbnail = match.artworkUrl100,
              let artURL = URL(string: thumbnail.replacingOccurrences(of: "100x100bb", with: "\(pixels)x\(pixels)bb"))
        else { return nil }
        var imageRequest = URLRequest(url: artURL)
        imageRequest.timeoutInterval = 12
        guard let (imageData, _) = try? await URLSession.shared.data(for: imageRequest) else { return nil }
        return NSImage(data: imageData)
    }

    private struct Search: Decodable {
        struct Song: Decodable {
            let trackName: String?
            let artistName: String?
            let artworkUrl100: String?
        }
        let results: [Song]
    }
}
