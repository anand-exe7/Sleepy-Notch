import SwiftUI
import AppKit

/// The collapsed notch.
///
/// A MacBook's notch is a cutout with no pixels, so nothing drawn inside it
/// can be seen. While music plays the notch grows a small wing on each side —
/// the cover on the left, still waveform bars on the right — and the middle
/// stays empty over the camera. With nothing playing it's exactly the notch.
///
/// A floating pill (a display with no notch) has room for the title as well.
///
/// Nothing here animates on its own; the cover only transitions once when
/// the song changes.
struct CompactNotchView: View {
    @ObservedObject var media: PlaybackCoordinator
    let collapsedSize: CGSize
    let notchWidth: CGFloat
    let isPhysicalNotch: Bool
    let showsWings: Bool
    let artworkStyle: ArtworkTransitionStyle
    /// Shared with the card, so collapsed and open use the same colour.
    let accentColor: Color
    /// Files waiting on the shelf, shown in the wings when nothing plays.
    let shelfCount: Int

    init(
        media: PlaybackCoordinator,
        collapsedSize: CGSize,
        notchWidth: CGFloat,
        isPhysicalNotch: Bool,
        showsWings: Bool,
        artworkStyle: ArtworkTransitionStyle,
        accent: Color,
        shelfCount: Int
    ) {
        self.media = media
        self.collapsedSize = collapsedSize
        self.notchWidth = notchWidth
        self.isPhysicalNotch = isPhysicalNotch
        self.showsWings = showsWings
        self.artworkStyle = artworkStyle
        self.accentColor = accent
        self.shelfCount = shelfCount
    }

    private var isPlaying: Bool {
        media.currentTrack.isPlaying && !media.currentTrack.isPlaceholder
    }

    var body: some View {
        Group {
            if isPhysicalNotch {
                wings
            } else {
                pill
            }
        }
        .frame(width: collapsedSize.width, height: collapsedSize.height)
    }

    // MARK: - Notch with wings

    @ViewBuilder private var wings: some View {
        if showsWings {
            HStack(spacing: 0) {
                leftWing
                    .frame(width: NotchMetrics.wingWidth)
                // The camera housing. No pixels here, so nothing is drawn.
                Color.clear
                    .frame(width: notchWidth)
                rightWing
                    .frame(width: NotchMetrics.wingWidth)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var leftWing: some View {
        if isPlaying {
            miniCover(size: 20, cornerRadius: 5)
        } else if shelfCount > 0 {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
        }
    }

    @ViewBuilder private var rightWing: some View {
        if isPlaying {
            WaveformVisualizer(
                isPlaying: true,
                animates: false,
                tintColor: accentColor,
                barCount: 3,
                height: 12
            )
        } else if shelfCount > 0 {
            Text("\(shelfCount)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.Text.secondary)
        }
    }

    // MARK: - Floating pill (no notch)

    private var pill: some View {
        HStack(spacing: 8) {
            miniCover(size: 22, cornerRadius: 5)

            Text(media.currentTrack.isPlaceholder
                 ? media.currentTrack.title
                 : "\(media.currentTrack.title) · \(media.currentTrack.artist)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isPlaying ? Theme.Text.secondary : Theme.Text.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if shelfCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text("\(shelfCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundColor(Theme.Text.secondary)
            }

            WaveformVisualizer(
                isPlaying: isPlaying,
                animates: false,
                tintColor: accentColor,
                barCount: 3,
                height: 12
            )
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Cover

    /// On a song change it runs a mini version of the card's artwork
    /// transition, then sits still.
    private func miniCover(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ArtworkTransitionContainer(
            key: media.currentTrack.identityKey,
            style: artworkStyle,
            size: size,
            cornerRadius: cornerRadius
        ) {
            CoverArtView(
                image: media.currentTrack.artworkImage,
                size: size,
                cornerRadius: cornerRadius,
                placeholderIcon: "music.note"
            )
        }
    }
}
