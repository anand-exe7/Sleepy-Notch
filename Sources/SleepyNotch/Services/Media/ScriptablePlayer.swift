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

    /// `player position` is in seconds in both apps (only Spotify's track
    /// `duration` is in milliseconds).
    func seek(toSeconds seconds: Double) async throws {
        try await send("set player position to \(seconds)")
    }

    /// Where playback is right now, in seconds. Asked once per playback
    /// event — never polled. `nil` if the app isn't running (checked first,
    /// so asking never launches it) or doesn't answer.
    func position() async -> Double? {
        let script = """
        if application "\(appName)" is running then
            tell application "\(appName)" to return player position
        end if
        """
        guard let text = try? await AppleScriptRunner.shared.run(script).text else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
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

        let duration = source.normalizedDuration(Self.number(parts[4]))
        let position = source.normalizedPosition(Self.number(parts[5]), duration: duration)

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

    /// AppleScript formats reals with the user's decimal separator.
    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
