import SwiftUI

/// Which size the lock screen card's cover is at. Lives in a class because
/// the card's window outlives any one view.
@MainActor
final class LockScreenCardState: ObservableObject {
    @Published var isCoverLarge = false
}

/// The Now Playing card on the lock screen: cover, title, artist and the
/// transport buttons. Tapping the cover grows it into large art; tapping
/// again shrinks it back. Media only: never notifications or files.
struct LockScreenCardView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    @ObservedObject var state: LockScreenCardState
    @ObservedObject var preferences: HUDPreferences

    static let width: CGFloat = 320
    /// The window is this much bigger than the card, so its shadow and the
    /// large cover's growth never get clipped.
    static let margin: CGFloat = 24
    static let smallCover: CGFloat = 64
    static let largeCover: CGFloat = 256
    /// The tallest the card gets (cover large), so the window never resizes.
    static let maxHeight: CGFloat = 16 + largeCover + 12 + titlesHeight + gap + scrubberHeight + gap + controlsHeight + 16
    static var windowSize: CGSize {
        CGSize(width: width + 2 * margin, height: maxHeight + 2 * margin)
    }

    /// Unhurried and a little soft, so a tap mid-way turns it around
    /// smoothly.
    static let motion = Animation.spring(response: 0.5, dampingFraction: 0.82)

    private static let inset: CGFloat = 16
    private static let contentWidth = width - 2 * inset
    private static let titlesHeight: CGFloat = 40
    private static let scrubberHeight: CGFloat = 18
    private static let controlsHeight: CGFloat = 40
    private static let gap: CGFloat = 8

    private static func contentHeight(large: Bool) -> CGFloat {
        large
            ? largeCover + 12 + titlesHeight + gap + scrubberHeight + gap + controlsHeight
            : smallCover + 12 + scrubberHeight + gap + controlsHeight
    }

    /// One fixed layout whose numbers animate (the cover's size, the
    /// buttons' place, the card's height), so nothing snaps or overlaps
    /// part-way; only the two title blocks cross-fade, each staying put.
    var body: some View {
        let track = media.currentTrack
        let large = state.isCoverLarge
        let coverSize = large ? Self.largeCover : Self.smallCover

        ZStack(alignment: .topLeading) {
            cover(track, size: coverSize)

            // Beside the small cover.
            titles(track, centered: false)
                .frame(width: Self.contentWidth - Self.smallCover - 14, height: Self.titlesHeight, alignment: .leading)
                .offset(x: Self.smallCover + 14, y: (Self.smallCover - Self.titlesHeight) / 2)
                .opacity(large ? 0 : 1)
                .animation(.easeOut(duration: 0.14), value: large)

            // Under the large one.
            titles(track, centered: true)
                .frame(width: Self.contentWidth, height: Self.titlesHeight, alignment: .top)
                .offset(y: Self.largeCover + 12)
                .opacity(large ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(large ? 0.12 : 0), value: large)

            PlayerScrubber(media: media, power: power, accentColor: preferences.highlightColor, onLockScreen: true)
                .frame(width: Self.contentWidth, height: Self.scrubberHeight)
                .offset(y: Self.contentHeight(large: large) - Self.controlsHeight - Self.gap - Self.scrubberHeight)

            TransportControls(media: media)
                .frame(width: Self.contentWidth, height: Self.controlsHeight)
                .offset(y: Self.contentHeight(large: large) - Self.controlsHeight)
        }
        .frame(width: Self.contentWidth, height: Self.contentHeight(large: large), alignment: .topLeading)
        .padding(Self.inset)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
        )
        .environment(\.colorScheme, .dark)
        .animation(Self.motion, value: large)
        // Anchored at the bottom, so the card grows upward, away from the
        // name and password prompt under it.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
        .padding(.bottom, Self.margin)
    }

    private func cover(_ track: TrackInfo, size: CGFloat) -> some View {
        CoverArtView(image: track.artworkImage, size: size, cornerRadius: size > 100 ? 22 : 12)
            .onTapGesture {
                withAnimation(Self.motion) { state.isCoverLarge.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(state.isCoverLarge ? "Shrink album art" : "Enlarge album art")
    }

    private func titles(_ track: TrackInfo, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 13))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }
    }
}
