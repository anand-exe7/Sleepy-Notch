import SwiftUI
import AppKit

/// The collapsed notch.
///
/// On a MacBook it draws nothing at all: the notch is a cutout with no
/// pixels, and once the card closes the HUD should leave no trace.
///
/// A display without a notch gets a small floating pill instead (cover,
/// title, still waveform), since there's no hardware notch to hover.
///
/// Nothing here animates on its own; the cover only transitions once when
/// the song changes.
struct CompactNotchView: View {
    @ObservedObject var media: PlaybackCoordinator
    let collapsedSize: CGSize
    let isPhysicalNotch: Bool
    let artworkStyle: ArtworkTransitionStyle
    /// Shared with the card, so collapsed and open use the same colour.
    let accentColor: Color
    /// Files waiting on the shelf, shown as a count in the pill.
    let shelfCount: Int

    init(
        media: PlaybackCoordinator,
        collapsedSize: CGSize,
        isPhysicalNotch: Bool,
        artworkStyle: ArtworkTransitionStyle,
        accent: Color,
        shelfCount: Int
    ) {
        self.media = media
        self.collapsedSize = collapsedSize
        self.isPhysicalNotch = isPhysicalNotch
        self.artworkStyle = artworkStyle
        self.accentColor = accent
        self.shelfCount = shelfCount
    }

    private var isPlaying: Bool {
        media.currentTrack.isPlaying && !media.currentTrack.isPlaceholder
    }

    var body: some View {
        Group {
            if !isPhysicalNotch {
                pill
            }
        }
        .frame(width: collapsedSize.width, height: collapsedSize.height)
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
