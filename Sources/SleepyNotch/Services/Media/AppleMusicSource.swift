import AppKit

/// Apple Music. Track changes arrive as `com.apple.Music.playerInfo`
/// distributed notifications — no polling — and commands go out as
/// AppleScript.
@MainActor
final class AppleMusicSource: PlaybackSource {
    let kind = MusicSource.appleMusic
    var onUpdate: ((TrackInfo) -> Void)?

    private let player = ScriptablePlayer(appName: "Music", kind: .appleMusic)
    /// Bumped per notification, so a slow position answer for an older one
    /// can't overwrite a newer one.
    private var generation = 0
    /// What was last passed on, to fall back on when Music doesn't answer.
    private var lastPublished: TrackInfo?

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Stopped means Music is quitting or has nothing loaded:
                // there's no song any more, so nothing to show.
                if userInfo?["Player State"] as? String == "Stopped" {
                    self.generation += 1
                    self.lastPublished = nil
                    self.onUpdate?(TrackInfo())
                    return
                }
                guard let track = Self.track(from: userInfo) else { return }
                await self.publish(track, askingPosition: true)
            }
        }
    }

    /// Music's notification says what's playing but not *where* — it has no
    /// playback position. Without one, every play, pause or seek reset the
    /// timeline to 0:00. So each notification asks Music once for the real
    /// position before passing the track on.
    private func publish(_ track: TrackInfo, askingPosition: Bool) async {
        generation += 1
        let current = generation
        var track = track
        if askingPosition, let position = await player.position() {
            guard current == generation else { return }
            track.position = min(max(position, 0), track.duration)
            track.lastUpdated = Date()
        } else if let last = lastPublished, last.identityKey == track.identityKey {
            // No answer: carry on from where the same song was, rather than
            // snapping back to 0:00.
            track.position = last.position(at: Date())
        }
        lastPublished = track
        onUpdate?(track)
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

        // No position here (`Location` is the file's URL, not a time); the
        // caller asks Music for it.
        return TrackInfo(
            title: title,
            artist: artist,
            album: userInfo["Album"] as? String ?? "",
            duration: duration > 0 ? duration : 180,
            position: 0,
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
    func currentPosition() async -> Double? { await player.position() }

    /// Music hands over the embedded artwork's raw image data directly. A
    /// song streamed from Apple Music has none to hand over (scripts see no
    /// artworks on it), so its cover comes from Apple's public catalogue
    /// search, by title and artist.
    func artwork(for track: TrackInfo) async -> NSImage? {
        let script = """
        tell application "Music"
            if (exists current track) and (name of current track is \(AppleScriptRunner.literal(track.title))) then
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
                return "no embedded artwork"
            end if
        end tell
        """
        guard let result = try? await AppleScriptRunner.shared.run(script) else { return nil }
        if let data = result.data, let image = NSImage(data: data) { return image }
        guard result.text == "no embedded artwork" else { return nil }
        return await CatalogueArtwork.image(title: track.title, artist: track.artist, pixels: 1000)
    }
}
