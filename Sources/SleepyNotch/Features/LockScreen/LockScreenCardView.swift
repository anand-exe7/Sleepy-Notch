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
/// It starts as a small pill that hugs what it shows (the cover, the song,
/// a play button), centred, so the words sit in the middle rather than
/// beside a stretch of empty glass. Clicking it grows the one glass shape
/// up and out into the full card, the way the Dynamic Island opens: the
/// cover and the titles fly to their places in the card (they are the same
/// pieces, not a second copy fading in), and the scrubber and controls
/// rise in a beat later. Clicking the cover in the card fills the screen
/// with the art. Media only: never notifications or files.
struct LockScreenCardView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    @ObservedObject var state: LockScreenCardState
    @ObservedObject var preferences: HUDPreferences
    @Namespace private var morph

    static let width: CGFloat = 360
    static let pillHeight: CGFloat = 60
    static let cardHeight: CGFloat = 196
    /// The window is this much bigger than the card, so the glass's edge
    /// and the spring's overshoot never get clipped.
    static let margin: CGFloat = 28
    static var windowSize: CGSize {
        CGSize(width: width + 2 * margin, height: cardHeight + 2 * margin)
    }

    /// The glass growing between pill and card: quick to start, settling
    /// with a little give, like the Dynamic Island.
    static let motion = Animation.spring(response: 0.5, dampingFraction: 0.8)

    private static let inset: CGFloat = 18
    private static let cover: CGFloat = 64
    private static let pillCover: CGFloat = 40
    private static let pillTitleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    private static let pillArtistFont = NSFont.systemFont(ofSize: 12)
    /// The pill's titles never take more than this; longer ones end in "…".
    private static let pillTitleLimit: CGFloat = 180
    private static let pillPlay: CGFloat = 34

    var body: some View {
        let expanded = state.isExpanded
        ZStack(alignment: .bottom) {
            // One glass shape for both: only its size and corners change.
            GlassPanelBackground(cornerRadius: expanded ? 30 : Self.pillHeight / 2)
                .frame(width: expanded ? Self.width : pillWidth, height: expanded ? Self.cardHeight : Self.pillHeight)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

            if expanded {
                card
                    .frame(width: Self.width, height: Self.cardHeight)
            } else {
                pill
                    .frame(width: pillWidth, height: Self.pillHeight)
            }
        }
        .frame(width: Self.width, height: Self.cardHeight, alignment: .bottom)
        .environment(\.colorScheme, .dark)
        // The scrubber and the bars run on the lock screen too.
        .environment(\.notchCardActive, true)
        .animation(Self.motion, value: expanded)
        .animation(Self.motion, value: pillWidth)
        // Hidden while the art fills the screen; it has its own controls.
        .opacity(state.showsArt ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: state.showsArt)
        // Anchored at the bottom, so it grows upward, away from the name
        // and password prompt under it.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
        .padding(.bottom, Self.margin)
    }

    private var track: TrackInfo { media.currentTrack }

    /// The pill fits its song: cover, titles (up to a limit) and the play
    /// button, measured from the text, so nothing has to be laid out twice.
    private var pillWidth: CGFloat {
        let title = (track.title as NSString).size(withAttributes: [.font: Self.pillTitleFont]).width
        let artist = (track.artist as NSString).size(withAttributes: [.font: Self.pillArtistFont]).width
        let text = min(Self.pillTitleLimit, ceil(max(title, artist, 60)))
        return min(Self.width, 10 + Self.pillCover + 11 + text + 10 + Self.pillPlay + 10)
    }

    // MARK: - Shared pieces

    /// The cover, one piece that grows from the pill into the card.
    private func coverArt(size: CGFloat, radius: CGFloat) -> some View {
        MorphingCover(image: track.artworkImage, cornerRadius: radius)
            .matchedGeometryEffect(id: "cover", in: morph)
            .frame(width: size, height: size)
    }

    private func titles(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track.title)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: size - 1.5))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }
        .matchedGeometryEffect(id: "titles", in: morph, anchor: .leading)
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 0) {
            coverArt(size: Self.pillCover, radius: 11)
                .padding(.trailing, 11)
            titles(size: 13.5)
                .frame(maxWidth: Self.pillTitleLimit, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            Button { media.togglePlayPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .frame(width: Self.pillPlay, height: Self.pillPlay)
                    .id(track.isPlaying)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .buttonStyle(PressScaleButtonStyle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: track.isPlaying)
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")
            .transition(.opacity.animation(.easeOut(duration: 0.12)))
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(Self.motion) { state.isExpanded = true } }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the player")
    }

    // MARK: - Card

    /// The card's own pieces rise in once the glass has mostly grown, and
    /// leave at once when it shrinks.
    private static let rise = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 10))
            .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.12)),
        removal: .opacity.animation(.easeOut(duration: 0.1))
    )

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                coverArt(size: Self.cover, radius: 18)
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
                .transition(Self.rise)
            }
            Group {
                PlayerScrubber(media: media, power: power, accentColor: preferences.highlightColor, onLockScreen: true)
                    .frame(height: 18)
                    .padding(.top, 16)
                TransportControls(media: media)
                    .frame(height: 40)
                    .padding(.top, 8)
            }
            .transition(Self.rise)
        }
        .padding(Self.inset)
    }
}

/// The album art filling whatever frame it's given, so it can grow
/// smoothly from the pill's size to the card's.
private struct MorphingCover: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(white: 0.16))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}
