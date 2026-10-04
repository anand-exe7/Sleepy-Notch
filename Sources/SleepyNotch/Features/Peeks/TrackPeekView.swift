import SwiftUI

/// "Now playing" peek on a song change. It opens on the *previous* cover and
/// swaps to the new one with the chosen artwork transition, so the change
/// itself is what you see.
struct TrackPeekView: View {
    let change: TrackChange
    @ObservedObject var media: PlaybackCoordinator
    let style: ArtworkTransitionStyle

    @StateObject private var reveal = CoverReveal()

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
        HStack(spacing: 12) {
            ArtworkTransitionContainer(
                key: shownCover.key,
                style: style,
                size: 40,
                cornerRadius: 9
            ) {
                CoverArtView(
                    image: shownCover.artwork,
                    size: 40,
                    cornerRadius: 9,
                    placeholderIcon: shownCover.source.iconName
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(current.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(current.artist)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Text.tertiary)
        }
        .padding(.horizontal, 18)
        .onAppear {
            // Let the peek finish dropping before the cover changes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                reveal.showsCurrent = true
            }
        }
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class CoverReveal: ObservableObject {
    @Published var showsCurrent = false
}
