import Foundation

/// What plays after the current song, for the floating player's Playing Next
/// list.
///
/// Only Apple Music can say: it lists the tracks of the playlist or album
/// being played, so the next ones are the ones after the current in it.
/// Spotify offers no queue to scripts, and Apple Music in shuffle has no
/// order to show, so there the list is hidden rather than guessed.
///
/// One script run when the list is asked for (the player opens, the song
/// changes); nothing is watched.
@MainActor
final class UpNextService: ObservableObject {
    struct Item: Identifiable, Equatable {
        /// The track's place in the playlist, which is how it's played.
        let id: Int
        let title: String
        let artist: String
    }

    @Published private(set) var items: [Item] = []

    private var generation = 0
    nonisolated private static let separator = "<<>>"
    nonisolated private static let field = "|||"

    func refresh(for track: TrackInfo) {
        generation += 1
        let current = generation
        guard track.source == .appleMusic, !track.isPlaceholder else {
            if !items.isEmpty { items = [] }
            return
        }
        let script = """
        tell application "Music"
            if player state is stopped then return "stopped"
            if shuffle enabled then return "shuffle"
            set cp to current playlist
            set total to count of tracks of cp
            set i to index of current track
            set out to {}
            repeat with n from (i + 1) to (i + 6)
                if n > total then exit repeat
                set t to track n of cp
                set end of out to (n as string) & "\(Self.field)" & (name of t) & "\(Self.field)" & (artist of t)
            end repeat
            set AppleScript's text item delimiters to "\(Self.separator)"
            return out as text
        end tell
        """
        Task { [weak self] in
            let text = (try? await AppleScriptRunner.shared.run(script).text) ?? ""
            guard let self, current == self.generation else { return }
            self.items = Self.parse(text)
        }
    }

    /// Plays one of the listed tracks.
    func play(_ item: Item) {
        let script = "tell application \"Music\" to play (track \(item.id) of current playlist)"
        Task { _ = try? await AppleScriptRunner.shared.run(script) }
    }

    nonisolated static func parse(_ text: String) -> [Item] {
        guard !text.isEmpty, text != "stopped", text != "shuffle" else { return [] }
        return text.components(separatedBy: separator).compactMap { entry in
            let parts = entry.components(separatedBy: field)
            guard parts.count >= 3, let id = Int(parts[0]) else { return nil }
            return Item(id: id, title: parts[1], artist: parts[2])
        }
    }
}
