import SwiftUI

/// "Now playing" peek on a song change. It opens on the *previous* cover and
/// swaps to the new one with the chosen artwork transition, so the change
/// itself is what you see.
struct TrackPeekView: View {
    let change: TrackChange
    @ObservedObject var media: PlaybackCoordinator
    let style: ArtworkTransitionStyle

    @StateObject private var reveal = CoverReveal()

    /// How far it drops below the notch: one tight row, close under it.
    static let contentHeight: CGFloat = 38
    private static let coverSize: CGFloat = 28
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let artistFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)

    /// The body's width for this song: as wide as its title and artist
    /// need, between a little wider than the notch and a set limit, so a
    /// short title isn't lost in black and a long one doesn't spread across
    /// the screen.
    static func width(for change: TrackChange, notchWidth: CGFloat) -> CGFloat {
        let title = (change.current.title as NSString).size(withAttributes: [.font: titleFont]).width
        let artist = (change.current.artist as NSString).size(withAttributes: [.font: artistFont]).width
        // Padding, cover, gaps and the note.
        let chrome: CGFloat = 16 + coverSize + 10 + 10 + 12 + 16
        let wanted = ceil(max(title, artist)) + chrome
        return min(notchWidth + 190, max(notchWidth + 70, wanted))
    }

    /// Artwork often lands a moment after the track change (Spotify fetches
    /// it over the network), so read the live track while it's still current.
    private var current: TrackSnapshot {
        media.currentTrack.identityKey == change.current.key
            ? TrackSnapshot(media.currentTrack)
            : change.current
    }

    private var shownCover: TrackSnapshot {
        reveal.showsCurrent ? current : change.previous
    }

    var body: some View {
        HStack(spacing: 10) {
            ArtworkTransitionContainer(
                key: shownCover.key,
                style: style,
                size: Self.coverSize,
                cornerRadius: 7
            ) {
                CoverArtView(
                    image: shownCover.artwork,
                    size: Self.coverSize,
                    cornerRadius: 7,
                    placeholderIcon: shownCover.source.iconName
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(current.title)
                    .font(Font(Self.titleFont))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(current.artist)
                    .font(Font(Self.artistFont))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.tertiary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        // Up against the notch rather than centred in the drop.
        .padding(.bottom, 3)
        .onAppear {
            // Let the peek finish dropping before the cover changes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                reveal.showsCurrent = true
            }
        }
    }
}

/// See `NotchInteractionState` for why this isn't `@State`.
private final class CoverReveal: ObservableObject {
    @Published var showsCurrent = false
}
