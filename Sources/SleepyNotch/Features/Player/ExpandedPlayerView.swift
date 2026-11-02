import SwiftUI

/// The open music card: cover, title and a small live equalizer, then the
/// timeline and the transport controls. Styled after the system's own Now
/// Playing — San Francisco type, white controls without backgrounds, colour
/// only for warnings. Laid out like Droppy's: the cover beside the camera,
/// the title just under the notch, so the card stays compact.
struct ExpandedPlayerView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject private var power: PowerStateMonitor
    let metrics: NotchMetrics
    /// Scrubber colour, decided by `NotchView` (white unless the album tint
    /// setting is on) so the card and the collapsed notch agree.
    let accentColor: Color

    static let coverSize: CGFloat = 52
    static let coverRadius: CGFloat = 11
    /// Inset from the card's left and right edges.
    static let sideInset: CGFloat = 22
    /// How far the cover reaches up beside the notch. The text column is
    /// bottom-aligned with it, so its top lands at the notch's bottom edge.
    static let coverRise: CGFloat = 8

    init(
        media: PlaybackCoordinator,
        power: PowerStateMonitor,
        metrics: NotchMetrics,
        accent: Color
    ) {
        self.media = media
        self.power = power
        self.metrics = metrics
        self.accentColor = accent
    }

    /// Hidden while the notch is closed (see `notchCardActive`).
    @Environment(\.notchCardActive) private var cardActive

    private var isPlaying: Bool {
        media.currentTrack.isPlaying && !media.currentTrack.isPlaceholder
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            PlayerScrubber(media: media, power: power, accentColor: accentColor)
                .padding(.top, 14)
            TransportControls(media: media)
                .padding(.top, 6)
        }
        .padding(.horizontal, Self.sideInset)
        .frame(width: metrics.cardWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // MarqueeText only scrolls when the title overflows, and
                    // holds still while paused or when motion isn't welcome.
                    MarqueeText(
                        media.currentTrack.title,
                        font: .system(size: 15, weight: .semibold),
                        color: Theme.Text.primary,
                        speed: 26,
                        animates: isPlaying && power.allowsDecorativeMotion && cardActive
                    )
                    .frame(height: 19)

                    status
                }

                Text(media.currentTrack.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
                    .frame(height: 16)
            }
            .padding(.bottom, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Beside the title: the equalizer, or a warning when Music or Spotify
    /// refused a command.
    @ViewBuilder
    private var status: some View {
        Group {
            // Only when Music/Spotify refused a command. When the fix is
            // Automation access, clicking opens that setting; otherwise the
            // tooltip says what happened.
            if let error = media.lastError {
                Group {
                    if error.isFixedInSystemSettings {
                        Button { SystemSettings.openAutomation() } label: { warningGlyph }
                            .buttonStyle(PressScaleButtonStyle())
                    } else {
                        warningGlyph
                    }
                }
                .help(error.helpText)
                .accessibilityLabel(error.shortDescription)
            } else {
                // Room for the bars, which `NotchView` draws (see `artwork`).
                Color.clear.frame(width: StatusWingsView.barsSize.width, height: StatusWingsView.barsSize.height)
            }
        }
    }

    private var warningGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.Status.warning)
            .frame(width: 18, height: 18)
    }

    /// Room for the cover. The cover itself is drawn by `NotchView`, shared
    /// with the closed notch's wings, so it can fly between the two.
    private var artwork: some View {
        Color.clear.frame(width: Self.coverSize, height: Self.coverSize)
    }

    /// Where the title row's middle sits, from the top of the header.
    static var titleMidY: CGFloat {
        coverSize - 1 - 16 - 2 - 19 / 2
    }
}
