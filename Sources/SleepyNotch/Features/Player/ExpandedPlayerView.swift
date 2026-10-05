import SwiftUI

/// The open music card: cover and title, a scrubber, transport controls, and
/// a Siri-style wave along the bottom while a song plays. Styled after the
/// system's own Now Playing — San Francisco type, white controls without
/// backgrounds, colour only for warnings. Rows arrive one after another as
/// the card opens.
struct ExpandedPlayerView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject private var power: PowerStateMonitor
    let metrics: NotchMetrics
    let artworkStyle: ArtworkTransitionStyle
    /// Scrubber colour, decided by `NotchView` (white unless the Lab's album
    /// tint is on) so the card and the collapsed notch agree.
    let accentColor: Color

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

    var body: some View {
        VStack(spacing: 0) {
            header
                .revealOnAppear(order: 0)
            PlayerScrubber(media: media, power: power, accentColor: accentColor)
                .padding(.top, 10)
                .revealOnAppear(order: 1)
            TransportControls(media: media)
                .padding(.top, 6)
                .revealOnAppear(order: 2)
            MusicWave(
                isActive: media.currentTrack.isPlaying && power.allowsDecorativeMotion,
                color: accentColor
            )
            .frame(height: 18)
            .revealOnAppear(order: 3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(width: metrics.cardWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                // MarqueeText only scrolls when the title overflows, and
                // holds still while paused or when motion isn't welcome.
                MarqueeText(
                    media.currentTrack.title,
                    font: .system(size: 14, weight: .semibold),
                    color: Theme.Text.primary,
                    speed: 26,
                    animates: media.currentTrack.isPlaying && power.allowsDecorativeMotion
                )
                .frame(height: 18)

                Text(media.currentTrack.artist)
                    .font(.system(size: 12))
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
            }
        }
    }

    /// Just the cover, crisp, with a hairline edge. Grey placeholder until
    /// artwork arrives.
    private var artwork: some View {
        let track = media.currentTrack
        return ArtworkTransitionContainer(
            key: track.identityKey,
            style: artworkStyle,
            size: 48,
            cornerRadius: 9
        ) {
            CoverArtView(
                image: track.artworkImage,
                size: 48,
                cornerRadius: 9,
                placeholderIcon: track.source.iconName
            )
        }
    }
}
