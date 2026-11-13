import SwiftUI

/// What the lock screen is showing. Lives in a class because the windows
/// outlive any one view.
@MainActor
final class LockScreenCardState: ObservableObject {
    /// The pill has been clicked open into the full card.
    @Published var isExpanded = false
    /// The album art fills the whole screen (see `LockScreenArtView`).
    @Published var showsArt = false
}

/// Now Playing on the lock screen, on Apple's glass.
///
/// It starts as a small pill: the cover, the song and a play button.
/// Clicking it grows it upward into the full card (cover, song, scrubber,
/// controls), one glass shape stretching, with the pill's pieces fading out
/// and the card's fading in. Clicking the cover in the card fills the whole
/// screen with the art. Media only: never notifications or files.
struct LockScreenCardView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    @ObservedObject var state: LockScreenCardState
    @ObservedObject var preferences: HUDPreferences

    static let width: CGFloat = 360
    static let pillHeight: CGFloat = 64
    static let cardHeight: CGFloat = 196
    /// The window is this much bigger than the card, so the glass's edge
    /// and the spring's overshoot never get clipped.
    static let margin: CGFloat = 28
    static var windowSize: CGSize {
        CGSize(width: width + 2 * margin, height: cardHeight + 2 * margin)
    }

    /// The glass stretching between pill and card: a little give.
    static let motion = Animation.spring(response: 0.48, dampingFraction: 0.78)

    private static let inset: CGFloat = 18
    private static let cover: CGFloat = 64
    private static let pillCover: CGFloat = 42

    var body: some View {
        let expanded = state.isExpanded
        ZStack(alignment: .bottom) {
            GlassPanelBackground(cornerRadius: expanded ? 30 : Self.pillHeight / 2)
                .frame(width: Self.width, height: expanded ? Self.cardHeight : Self.pillHeight)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

            pill
                .frame(width: Self.width, height: Self.pillHeight)
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 0.94 : 1, anchor: .bottom)
                .allowsHitTesting(!expanded)
                .animation(.easeOut(duration: expanded ? 0.12 : 0.24).delay(expanded ? 0 : 0.14), value: expanded)

            card
                .frame(width: Self.width, height: Self.cardHeight)
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.96, anchor: .bottom)
                .allowsHitTesting(expanded)
                .animation(.easeOut(duration: expanded ? 0.26 : 0.12).delay(expanded ? 0.12 : 0), value: expanded)
        }
        .environment(\.colorScheme, .dark)
        // The scrubber and the bars run on the lock screen too.
        .environment(\.notchCardActive, true)
        .animation(Self.motion, value: expanded)
        // Hidden while the art fills the screen; it has its own controls.
        .opacity(state.showsArt ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: state.showsArt)
        // Anchored at the bottom, so it grows upward, away from the name
        // and password prompt under it.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
        .padding(.bottom, Self.margin)
    }

    private var track: TrackInfo { media.currentTrack }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 12) {
            CoverArtView(image: track.artworkImage, size: Self.pillCover, cornerRadius: 14)
            titles(size: 14)
            Spacer(minLength: 4)
            Button { media.togglePlayPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .frame(width: 36, height: 36)
                    .id(track.isPlaying)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .buttonStyle(PressScaleButtonStyle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: track.isPlaying)
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")
        }
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(Self.motion) { state.isExpanded = true } }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the player")
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CoverArtView(image: track.artworkImage, size: Self.cover, cornerRadius: 20)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.35)) { state.showsArt = true } }
                    .help("Show the album art full screen")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Show album art full screen")
                titles(size: 16)
                Spacer(minLength: 0)
                Button { withAnimation(Self.motion) { state.isExpanded = false } } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.Text.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Make smaller")
            }
            PlayerScrubber(media: media, power: power, accentColor: preferences.highlightColor, onLockScreen: true)
                .frame(height: 18)
                .padding(.top, 16)
            TransportControls(media: media)
                .frame(height: 40)
                .padding(.top, 8)
        }
        .padding(Self.inset)
    }

    private func titles(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: size - 2))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }
    }
}
