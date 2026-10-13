import SwiftUI

/// The open music card: cover, title and a small live equalizer, then the
/// timeline and the transport controls. Styled after the system's own Now
/// Playing — San Francisco type, white controls without backgrounds, colour
/// only for warnings. Rows arrive one after another as the card opens.
struct ExpandedPlayerView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject private var power: PowerStateMonitor
    let metrics: NotchMetrics
    let artworkStyle: ArtworkTransitionStyle
    /// Scrubber colour, decided by `NotchView` (white unless the Lab's album
    /// tint is on) so the card and the collapsed notch agree.
    let accentColor: Color

    private static let coverSize: CGFloat = 58

    init(
        media: PlaybackCoordinator,
        power: PowerStateMonitor,
        metrics: NotchMetrics,
        artworkStyle: ArtworkTransitionStyle,
        accent: Color
    ) {
        self.media = media
        self.power = power
        self.metrics = metrics
        self.artworkStyle = artworkStyle
        self.accentColor = accent
    }

    private var isPlaying: Bool {
        media.currentTrack.isPlaying && !media.currentTrack.isPlaceholder
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .revealOnAppear(order: 0)
            PlayerScrubber(media: media, power: power, accentColor: accentColor)
                .padding(.top, 14)
                .revealOnAppear(order: 1)
            TransportControls(media: media)
                .padding(.top, 6)
                .revealOnAppear(order: 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .frame(width: metrics.cardWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                // MarqueeText only scrolls when the title overflows, and
                // holds still while paused or when motion isn't welcome.
                MarqueeText(
                    media.currentTrack.title,
                    font: .system(size: 15, weight: .semibold),
                    color: Theme.Text.primary,
                    speed: 26,
                    animates: isPlaying && power.allowsDecorativeMotion
                )
                .frame(height: 19)

                Text(media.currentTrack.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Only when Music/Spotify refused a command — usually missing
            // Automation access. Click to open the setting.
            if let error = media.lastError {
                Button { SystemSettings.openAutomation() } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Status.warning)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PressScaleButtonStyle())
                .help(error.helpText)
            } else {
                EqualizerBars(
                    isPlaying: isPlaying,
                    animates: power.allowsDecorativeMotion,
                    color: accentColor
                )
                .frame(width: 22, height: 18)
            }
        }
    }

    /// The cover, crisp, with a hairline edge. It sits back a little while
    /// paused and springs forward when the music starts, like Music's own
    /// player. Grey placeholder until artwork arrives.
    private var artwork: some View {
        let track = media.currentTrack
        return ArtworkTransitionContainer(
            key: track.identityKey,
            style: artworkStyle,
            size: Self.coverSize,
            cornerRadius: 12
        ) {
            CoverArtView(
                image: track.artworkImage,
                size: Self.coverSize,
                cornerRadius: 12,
                placeholderIcon: track.source.iconName
            )
        }
        .scaleEffect(isPlaying || track.isPlaceholder ? 1 : 0.88)
        .opacity(isPlaying || track.isPlaceholder ? 1 : 0.8)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: isPlaying)
    }
}
