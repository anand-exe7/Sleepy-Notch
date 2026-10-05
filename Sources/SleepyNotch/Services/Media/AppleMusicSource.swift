import AppKit

/// Apple Music. Track changes arrive as `com.apple.Music.playerInfo`
/// distributed notifications — no polling — and commands go out as
/// AppleScript.
@MainActor
final class AppleMusicSource: PlaybackSource {
    let kind = MusicSource.appleMusic
    var onUpdate: ((TrackInfo) -> Void)?

    private let player = ScriptablePlayer(appName: "Music", kind: .appleMusic)

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
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
    /// Music doesn't include it, so it's fetched separately.
    static func track(from userInfo: [AnyHashable: Any]?) -> TrackInfo? {
        guard let userInfo else { return nil }

        let title = userInfo["Name"] as? String ?? "Unknown Title"
        let artist = userInfo["Artist"] as? String ?? "Unknown Artist"

        // Total time is sometimes in milliseconds, sometimes seconds.
        var duration: Double = 180
        if let total = userInfo["Total Time"] as? NSNumber {
            let value = total.doubleValue
            duration = value > 1000 ? value / 1000.0 : value
        }

        // Position isn't always included; without it, assume the start.
        let position = (userInfo["Location"] as? NSNumber)?.doubleValue ?? 0

        return TrackInfo(
            title: title,
            artist: artist,
            album: userInfo["Album"] as? String ?? "",
            duration: duration > 0 ? duration : 180,
            position: position,
            isPlaying: userInfo["Player State"] as? String == "Playing",
            source: .appleMusic,
            lastUpdated: Date()
        )
    }

    func togglePlayPause() async throws { try await player.togglePlayPause() }
    func nextTrack() async throws { try await player.nextTrack() }
    func previousTrack() async throws { try await player.previousTrack() }
    func seek(toSeconds seconds: Double) async throws { try await player.seek(toSeconds: seconds) }
    func currentStatus() async -> SourceStatus? { await player.status() }

    /// Music hands over the embedded artwork's raw image data directly.
    func artwork() async -> NSImage? {
        let script = """
        tell application "Music"
            if (exists current track) and (count of artworks of current track > 0) then
                return raw data of artwork 1 of current track
            end if
        end tell
        """
        guard let data = try? await AppleScriptRunner.shared.run(script).data else { return nil }
        return NSImage(data: data)
    }
}
