import AppKit

/// Spotify. Track changes arrive as `com.spotify.client.PlaybackStateChanged`
/// distributed notifications — no polling — and commands go out as
/// AppleScript.
@MainActor
final class SpotifySource: PlaybackSource {
    let kind = MusicSource.spotify
    var onUpdate: ((TrackInfo) -> Void)?

    private let player = ScriptablePlayer(appName: "Spotify", kind: .spotify)

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let track = Self.track(from: notification.userInfo) else { return }
                self.onUpdate?(track)
            }
        }
    }

    /// Builds a track from the notification's `userInfo`. No artwork:
    /// Spotify only gives a URL, fetched separately.
    static func track(from userInfo: [AnyHashable: Any]?) -> TrackInfo? {
        guard let userInfo else { return nil }

        let state = userInfo["Player State"] as? String ?? ""

        // Duration arrives in milliseconds, position in seconds.
        var duration: Double = 180
        if let raw = userInfo["Duration"] as? NSNumber {
            duration = MusicSource.spotify.normalizedDuration(raw.doubleValue)
        }
        var position: Double = 0
        if let raw = userInfo["Playback Position"] as? NSNumber {
            position = MusicSource.spotify.normalizedPosition(raw.doubleValue, duration: duration)
        }

        return TrackInfo(
            title: userInfo["Name"] as? String ?? "Unknown Title",
            artist: userInfo["Artist"] as? String ?? "Unknown Artist",
            album: userInfo["Album"] as? String ?? "",
            duration: duration > 0 ? duration : 180,
            position: min(position, duration > 0 ? duration : position),
            isPlaying: state == "Playing" || state == "kPSP",
            source: .spotify,
            lastUpdated: Date()
        )
    }

    func togglePlayPause() async throws { try await player.togglePlayPause() }
    func nextTrack() async throws { try await player.nextTrack() }
    func previousTrack() async throws { try await player.previousTrack() }
    func seek(toSeconds seconds: Double) async throws { try await player.seek(toSeconds: seconds) }
    func currentStatus() async -> SourceStatus? { await player.status() }

    /// Spotify exposes only an artwork URL, so this is one AppleScript call
    /// plus one download.
    func artwork() async -> NSImage? {
        let script = "tell application \"Spotify\" to get artwork url of current track"
        guard let urlString = try? await AppleScriptRunner.shared.run(script).text,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return NSImage(data: data)
    }
}
