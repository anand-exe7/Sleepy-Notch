import Foundation
import Combine
import CryptoKit

/// One line of a song's words and when it starts, in seconds.
struct LyricLine: Equatable {
    let time: Double
    let text: String
}

/// Synced lyrics for the current song, from LRCLIB (lrclib.net, free, no
/// account).
///
/// Cheap by design:
/// - nothing is fetched or timed unless a place that shows lyrics is on
///   screen (the open card, the floating player), and nothing at all while
///   the switch is off;
/// - a song is looked up once: the answer, found or not, is kept on disk;
/// - the current line changes with one one-shot timer, set for the moment
///   the next line begins; paused, or a seek, sets it again, and while
///   paused or hidden no timer exists.
///
/// What's sent to LRCLIB is the song's title, artist, album and length.
@MainActor
final class LyricsService: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case found
        case none
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [LyricLine] = []
    /// The line being sung now; nil before the first one.
    @Published private(set) var currentIndex: Int?

    /// The switch in Settings.
    var isEnabled = true {
        didSet { if isEnabled != oldValue { surfacesChanged() } }
    }

    private weak var playback: PlaybackCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var surfaces = Set<String>()
    private var loadedKey: String?
    private var loadTask: Task<Void, Never>?
    private var lineTimer: DispatchWorkItem?

    /// How early a line is shown, so it's on screen as it's sung.
    private static let lead: Double = 0.25

    func attach(to playback: PlaybackCoordinator) {
        self.playback = playback
        playback.$currentTrack
            .sink { [weak self] _ in
                // After the new value is stored.
                DispatchQueue.main.async { self?.trackChanged() }
            }
            .store(in: &cancellables)
    }

    /// A place that shows lyrics comes on screen or goes away.
    func setVisible(_ visible: Bool, surface: String) {
        if visible { surfaces.insert(surface) } else { surfaces.remove(surface) }
        surfacesChanged()
    }

    var currentLine: String? {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return nil }
        let text = lines[currentIndex].text
        return text.isEmpty ? "♪" : text
    }

    // MARK: - Following the song

    private var wanted: Bool { isEnabled && !surfaces.isEmpty }

    private func surfacesChanged() {
        if wanted {
            trackChanged()
        } else {
            lineTimer?.cancel()
            lineTimer = nil
            loadTask?.cancel()
            loadTask = nil
            if status == .loading { status = .idle; loadedKey = nil }
        }
    }

    private func trackChanged() {
        guard wanted, let track = playback?.currentTrack, !track.isPlaceholder else {
            lineTimer?.cancel()
            if playback?.currentTrack.isPlaceholder == true { reset(); loadedKey = nil }
            return
        }
        let key = Self.key(for: track)
        if key != loadedKey {
            loadedKey = key
            reset()
            load(track, key: key)
        } else {
            schedule()
        }
    }

    private func reset() {
        loadTask?.cancel()
        lineTimer?.cancel()
        lines = []
        currentIndex = nil
        status = .idle
    }

    /// Works out the line for where the song is, and sets one timer for the
    /// next change.
    private func schedule() {
        lineTimer?.cancel()
        lineTimer = nil
        guard wanted, status == .found, let track = playback?.currentTrack else { return }
        let position = track.position(at: Date()) + Self.lead
        var index: Int?
        for (offset, line) in lines.enumerated() where line.time <= position { index = offset }
        if index != currentIndex { currentIndex = index }
        guard track.isPlaying else { return }
        let next = (index.map { $0 + 1 } ?? 0)
        guard lines.indices.contains(next) else { return }
        let delay = max(0.05, lines[next].time - position)
        let work = DispatchWorkItem { [weak self] in self?.schedule() }
        lineTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Fetching

    private func load(_ track: TrackInfo, key: String) {
        status = .loading
        let title = track.title, artist = track.artist, album = track.album, duration = track.duration
        loadTask = Task { [weak self] in
            let synced = await LyricsStore.synced(title: title, artist: artist, album: album, duration: duration, key: key)
            guard !Task.isCancelled, let self, self.loadedKey == key else { return }
            if let synced, !synced.isEmpty {
                self.lines = synced
                self.status = .found
                self.schedule()
            } else {
                self.lines = []
                self.status = .none
            }
        }
    }

    nonisolated static func key(for track: TrackInfo) -> String {
        "\(track.artist)|\(track.title)|\(track.album)|\(Int(track.duration.rounded()))".lowercased()
    }
}

// MARK: - Disk cache and LRCLIB

enum LyricsStore {
    private struct Entry: Codable {
        var synced: String?
        var fetchedAt: Date
    }

    /// A song that had no lyrics is asked about again after this long.
    private static let missLifetime: TimeInterval = 7 * 24 * 3600
    private static let maxFiles = 400

    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sleepy Notch", isDirectory: true).appendingPathComponent("Lyrics", isDirectory: true)
    }

    private static func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    /// The song's synced lyrics, from disk if it was looked up before.
    static func synced(title: String, artist: String, album: String, duration: Double, key: String) async -> [LyricLine]? {
        let url = file(for: key)
        if let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data) {
            if entry.synced != nil || Date().timeIntervalSince(entry.fetchedAt) < missLifetime {
                return entry.synced.map(parse)
            }
        }
        // `nil` here means "couldn't ask" (offline) and isn't remembered;
        // an empty string means LRCLIB has nothing, which is.
        guard let text = await fetch(title: title, artist: artist, album: album, duration: duration) else { return nil }
        save(Entry(synced: text.isEmpty ? nil : text, fetchedAt: Date()), to: url)
        return text.isEmpty ? nil : parse(text)
    }

    private static func save(_ entry: Entry, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
           files.count > maxFiles {
            let oldest = files.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for file in oldest.prefix(100) { try? FileManager.default.removeItem(at: file) }
        }
        if let data = try? JSONEncoder().encode(entry) { try? data.write(to: url, options: .atomic) }
    }

    /// Asks LRCLIB. Returns the synced lyrics, "" for none, nil if it
    /// couldn't be reached.
    private static func fetch(title: String, artist: String, album: String, duration: Double) async -> String? {
        let seconds = Int(duration.rounded())
        // The exact match first.
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(seconds)),
        ]
        switch await request(exact.url!) {
        case .failure: return nil
        case .success(let data?):
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let synced = json["syncedLyrics"] as? String, !synced.isEmpty { return synced }
        case .success(nil): break
        }
        // Then a search, taking the closest length: the album or the length
        // often differs between releases.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        switch await request(search.url!) {
        case .failure: return nil
        case .success(let data?):
            let results = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            let best = results
                .compactMap { item -> (String, Double)? in
                    guard let synced = item["syncedLyrics"] as? String, !synced.isEmpty,
                          let length = (item["duration"] as? NSNumber)?.doubleValue else { return nil }
                    return (synced, abs(length - duration))
                }
                .filter { $0.1 <= 6 }
                .min { $0.1 < $1.1 }
            return best?.0 ?? ""
        case .success(nil): return ""
        }
    }

    private enum Reply {
        case success(Data?)
        case failure
    }

    private static func request(_ url: URL) async -> Reply {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Sleepy Notch (https://github.com/anand-exe7/Sleepy-Notch)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failure }
        switch status {
        case 200: return .success(data)
        case 404: return .success(nil)
        default: return .failure
        }
    }

    // MARK: - LRC

    /// "[01:23.45] words", with several stamps allowed per line and an
    /// optional "[offset:±ms]".
    static func parse(_ text: String) -> [LyricLine] {
        var offset = 0.0
        var lines: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let seconds = stamp(tag) {
                    times.append(seconds)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                    times = []
                    break
                } else {
                    times = []
                    break
                }
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            for time in times { lines.append(LyricLine(time: time, text: words)) }
        }
        return lines.map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }.sorted { $0.time < $1.time }
    }

    private static func stamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return minutes * 60 + seconds
    }
}
