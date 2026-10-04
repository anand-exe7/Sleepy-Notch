import SwiftUI
import AppKit

public final class PlayerUIState: ObservableObject {
    @Published public var isDraggingScrubber = false
    @Published public var dragRatio: Double = 0.0
    @Published public var isScrubberHovered = false
    @Published public var isPrevHovered = false
    @Published public var isPlayHovered = false
    @Published public var isNextHovered = false

    public init() {}
}

/// The open music card: cover and title, a scrubber, and transport controls.
/// Styled after the system's own Now Playing — San Francisco type, white
/// controls without backgrounds, colour only for warnings.
struct ExpandedPlayerView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject private var power = PowerStateMonitor.shared
    let metrics: NotchMetrics
    let artworkStyle: ArtworkTransitionStyle
    /// Scrubber colour, decided by `NotchView` (white unless the Lab's album
    /// tint is on) so the card and the collapsed notch agree.
    let accentColor: Color
    @StateObject private var ui = PlayerUIState()

    init(
        media: PlaybackCoordinator,
        metrics: NotchMetrics = .fallback,
        artworkStyle: ArtworkTransitionStyle = .flip,
        accent: Color
    ) {
        self.media = media
        self.metrics = metrics
        self.artworkStyle = artworkStyle
        self.accentColor = accent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .revealOnAppear(order: 0)
            scrubberView
                .padding(.top, 10)
                .revealOnAppear(order: 1)
            transport
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
            artworkView

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
                Button { openAutomationSettings() } label: {
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

    // MARK: - Artwork

    private var artworkView: some View {
        let track = media.currentTrack
        // Just the cover, crisp, with a hairline edge. Grey placeholder until
        // artwork arrives.
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

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 30) {
            TransportButton(symbol: "backward.fill", size: 16, isHovered: ui.isPrevHovered) {
                media.previousTrack()
            } onHover: { ui.isPrevHovered = $0 }

            TransportButton(
                symbol: media.currentTrack.isPlaying ? "pause.fill" : "play.fill",
                size: 24,
                isHovered: ui.isPlayHovered
            ) {
                media.togglePlayPause()
            } onHover: { ui.isPlayHovered = $0 }

            TransportButton(symbol: "forward.fill", size: 16, isHovered: ui.isNextHovered) {
                media.nextTrack()
            } onHover: { ui.isNextHovered = $0 }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scrubber

    /// The only part of the card that changes on its own. It ticks once a
    /// second while the track plays and the notch is visible; nothing else in
    /// the card redraws for it.
    private var scrubberView: some View {
        TimelineView(PlaybackClockSchedule(
            track: media.currentTrack,
            isActive: media.currentTrack.isPlaying && power.isNotchVisible
        )) { clock in
            scrubber(at: clock.date)
        }
    }

    /// Thin until you reach for it: hovering thickens the bar and shows the
    /// thumb, like the system's own scrubbers.
    private var isScrubberActive: Bool {
        ui.isScrubberHovered || ui.isDraggingScrubber
    }

    private func scrubber(at now: Date) -> some View {
        let barHeight: CGFloat = isScrubberActive ? 6 : 4
        let thumbSize: CGFloat = ui.isDraggingScrubber ? 12 : 10

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let ratio = ui.isDraggingScrubber ? ui.dragRatio : media.currentTrack.progressRatio(at: now)
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: barHeight)

                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(barHeight, min(w * ratio, w)), height: barHeight)

                    // Centred on the playhead and clamped so it never
                    // overhangs either end.
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .opacity(isScrubberActive ? 1 : 0)
                        .offset(x: max(0, min(w * ratio - thumbSize / 2, w - thumbSize)))
                }
                .frame(height: geo.size.height)
                .animation(.easeOut(duration: 0.15), value: isScrubberActive)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            ui.isDraggingScrubber = true
                            ui.dragRatio = max(0, min(v.location.x / w, 1))
                        }
                        .onEnded { v in
                            media.seek(to: max(0, min(v.location.x / w, 1)))
                            ui.isDraggingScrubber = false
                        }
                )
            }
            // A thin bar is hard to hit, so the drag target extends into the
            // space around it without changing the layout.
            .frame(height: 12)
            .contentShape(Rectangle().inset(by: -6))
            .onHover { ui.isScrubberHovered = $0 }

            HStack {
                let pos = ui.isDraggingScrubber ? ui.dragRatio * media.currentTrack.duration : media.currentTrack.position(at: now)
                Text(fmt(pos))
                Spacer()
                Text("-\(fmt(max(0, media.currentTrack.duration - pos)))")
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundColor(Theme.Text.tertiary)
        }
    }

    // MARK: - Helpers

    /// Opens the Automation pane of System Settings, where a denied permission
    /// is granted. `open` is a no-op in a bare `swift run` context without a
    /// bundle, but harmless.
    private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// A transport glyph with no chrome: white, a soft circle behind it on
/// hover, and a quick squeeze when pressed.
private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let isHovered: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 1 : 0.88))
                // Swapping play/pause pops instead of snapping.
                .id(symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .frame(width: size + 16, height: size + 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                )
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: symbol)
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover(perform: onHover)
    }
}

/// Shrinks slightly while held, springing back on release.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
