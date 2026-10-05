import Foundation

/// The AppleScript Music and Spotify have in common: the same transport
/// verbs and the same status query, differing only in the app's name and
/// the unit it reports time in.
///
/// Every script runs through `AppleScriptRunner`, off the main thread.
@MainActor
struct ScriptablePlayer {
    let appName: String
    let kind: MusicSource

    func togglePlayPause() async throws {
        try await send("playpause")
    }

    func nextTrack() async throws {
        try await send("next track")
    }

    func previousTrack() async throws {
        try await send("previous track")
    }

    /// `player position` is in the same unit the app reports time in, so a
    /// Spotify seek has to be scaled back up to milliseconds or the track
    /// jumps to the wrong offset.
    func seek(toSeconds seconds: Double) async throws {
        let raw = kind.usesMillisecondTime ? seconds * 1000.0 : seconds
        try await send("set player position to \(Int(raw))")
    }

    private func send(_ command: String) async throws {
        _ = try await AppleScriptRunner.shared.run("tell application \"\(appName)\" to \(command)")
    }

    // MARK: - Status

    /// Asks the app what it's doing. A failure isn't fatal — it just means
    /// this app can't be the active source.
    func status() async -> SourceStatus? {
        guard let result = try? await AppleScriptRunner.shared.run(statusScript) else { return nil }
        return Self.parseStatus(result.text, source: kind)
    }

    /// `state|||title|||artist|||album|||duration|||position`
    private static let separator = "|||"

    private var statusScript: String {
        """
        tell application "\(appName)"
            set playerState to (player state as string)
            if playerState is "stopped" then return "stopped"
            return playerState & "\(Self.separator)" & (get name of current track) & "\(Self.separator)" & (get artist of current track) & "\(Self.separator)" & (get album of current track) & "\(Self.separator)" & (get duration of current track) & "\(Self.separator)" & (get player position)
        end tell
        """
    }

    static func parseStatus(_ text: String?, source: MusicSource) -> SourceStatus? {
        guard let text else { return nil }
        let parts = text.components(separatedBy: separator)
        let state = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard state != "stopped" else {
            return SourceStatus(source: source, state: state, track: nil)
        }
        guard parts.count >= 6 else { return nil }

        // Duration and position arrive in the same unit, so both go through
        // the same normalisation.
        let duration = source.normalizedTime(Double(parts[4]) ?? 0)
        let position = source.normalizedTime(Double(parts[5]) ?? 0)

        let track = TrackInfo(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration > 0 ? duration : 180,
            position: min(position, duration > 0 ? duration : .greatestFiniteMagnitude),
            isPlaying: state == "playing",
            source: source,
            lastUpdated: Date()
        )
        return SourceStatus(source: source, state: state, track: track)
    }
}
