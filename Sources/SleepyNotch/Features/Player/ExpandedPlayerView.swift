import SwiftUI
import AppKit

public final class PlayerUIState: ObservableObject {
    @Published public var isDraggingScrubber = false
    @Published public var dragRatio: Double = 0.0
    @Published public var isPrevHovered = false
    @Published public var isPlayHovered = false
    @Published public var isNextHovered = false
    
    public init() {}
}

struct ExpandedPlayerView: View {
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject private var power = PowerStateMonitor.shared
    let metrics: NotchMetrics
    @StateObject private var ui = PlayerUIState()

    init(media: PlaybackCoordinator, metrics: NotchMetrics = .fallback) {
        self.media = media
        self.metrics = metrics
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // ═══ Top Row: Artwork + Track Info ═══
            HStack(spacing: 14) {
                artworkView
                
                VStack(alignment: .leading, spacing: 3) {
                    // Long titles used to be hard-truncated with an ellipsis.
                    // MarqueeText only animates when the text actually
                    // overflows, so short titles cost nothing — and it holds
                    // still while paused or when motion isn't welcome.
                    MarqueeText(
                        media.currentTrack.title,
                        font: .system(size: 13.5, weight: .bold, design: .rounded),
                        color: Theme.Text.primary,
                        speed: 26,
                        animates: media.currentTrack.isPlaying && power.allowsDecorativeMotion
                    )
                    .frame(height: 17)
                    .shadow(color: accentColor.opacity(0.2), radius: 4, y: 0)
                    
                    Text(media.currentTrack.artist)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                    
                    if !media.currentTrack.album.isEmpty {
                        Text(media.currentTrack.album)
                            .font(.system(size: 9.5, weight: .regular, design: .rounded))
                            .foregroundColor(Theme.Text.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Source badge (compact, icon-only)
                sourceBadge
            }
            
            // ═══ Scrubber ═══
            scrubberView
            
            // ═══ Transport Controls ═══
            HStack(spacing: 0) {
                // Left: waveform, plus either the demo badge or a failure notice
                HStack(spacing: 4) {
                    WaveformVisualizer(
                        isPlaying: media.currentTrack.isPlaying,
                        animates: power.allowsDecorativeMotion,
                        tintColor: accentColor,
                        barCount: 4,
                        height: 13
                    )
                    if let error = media.lastError {
                        // Replaces the demo badge: a live failure is more urgent
                        // than a mode indicator, and both can't be true at once
                        // in a way worth spending the space on.
                        Button { openAutomationSettings() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 7, weight: .bold))
                                Text("Fix")
                                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(Color(red: 0.85, green: 0.22, blue: 0.22).opacity(0.85))
                            )
                        }
                        .buttonStyle(.plain)
                        .help(error.helpText)
                    } else if media.isDemoMode {
                        Text("DEMO")
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundColor(accentColor.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .stroke(accentColor.opacity(0.3), lineWidth: 0.6)
                            )
                    }
                }
                .frame(width: 60, alignment: .leading)
                
                Spacer()
                
                // Center: transport buttons
                HStack(spacing: 22) {
                    transportButton(icon: "backward.fill", isHovered: ui.isPrevHovered) {
                        media.previousTrack()
                    } onHover: { ui.isPrevHovered = $0 }
                    
                    // Play/Pause — the hero button
                    Button { media.togglePlayPause() } label: {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [accentColor.opacity(0.15), Color.clear],
                                        center: .center,
                                        startRadius: 14,
                                        endRadius: 26
                                    )
                                )
                                .frame(width: 42, height: 42)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 33, height: 33)
                                .shadow(color: accentColor.opacity(0.35), radius: 8, y: 2)
                            
                            Image(systemName: media.currentTrack.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(Color(red: 0.06, green: 0.06, blue: 0.08))
                                .offset(x: media.currentTrack.isPlaying ? 0 : 1.2)
                        }
                        .scaleEffect(ui.isPlayHovered ? 1.1 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: ui.isPlayHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { ui.isPlayHovered = $0 }
                    
                    transportButton(icon: "forward.fill", isHovered: ui.isNextHovered) {
                        media.nextTrack()
                    } onHover: { ui.isNextHovered = $0 }
                }
                
                Spacer()
                
                // Right: mode toggle
                Button { media.toggleDemoMode() } label: {
                    Image(systemName: media.isDemoMode ? "sparkles" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Text.tertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 60, alignment: .trailing)
                .contentShape(Rectangle().inset(by: -10))
                .help(media.isDemoMode ? "Switch to Live Music" : "Demo Mode")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 2)
        .frame(width: metrics.cardWidth)
    }
    
    // MARK: - Transport Button
    
    private func transportButton(icon: String, isHovered: Bool, action: @escaping () -> Void, onHover: @escaping (Bool) -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 1 : 0.6))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.1 : 0))
                )
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        // The visual stays 30pt, but the tappable region grows to Apple's 44pt
        // minimum by reaching into the surrounding padding. No layout shift.
        .contentShape(Rectangle().inset(by: -7))
        .onHover(perform: onHover)
    }
    
    // MARK: - Artwork
    
    private var artworkView: some View {
        ZStack {
            if let art = media.currentTrack.artworkImage {
                // Ambient blur glow behind
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .blur(radius: 14)
                    .opacity(0.35)
                    .scaleEffect(1.25)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                // Procedural gradient cover
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.55),
                                    accentColor.opacity(0.2),
                                    Color(red: 0.06, green: 0.06, blue: 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: media.currentTrack.source.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .shadow(color: accentColor.opacity(0.3), radius: 8, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Source Badge
    
    private var sourceBadge: some View {
        Image(systemName: media.currentTrack.source.iconName)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(accentColor)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accentColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accentColor.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    // MARK: - Scrubber
    
    private var thumbSize: CGFloat {
        ui.isDraggingScrubber ? 10 : 7
    }
    
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

    private func scrubber(at now: Date) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let ratio = ui.isDraggingScrubber ? ui.dragRatio : media.currentTrack.progressRatio(at: now)
                let w = geo.size.width
                
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: 4)
                    
                    // Filled portion with gradient
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.55), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(w * ratio, w)), height: 4)
                    
                    // Thumb — an accent ring on drag makes the grab point
                    // unambiguous, which matters given the thin track.
                    ZStack {
                        Circle()
                            .fill(Theme.Text.primary)
                            .frame(width: thumbSize, height: thumbSize)
                            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                        if ui.isDraggingScrubber {
                            Circle()
                                .strokeBorder(accentColor.opacity(0.9), lineWidth: 2)
                                .frame(width: thumbSize + 6, height: thumbSize + 6)
                        }
                    }
                    .shadow(color: accentColor.opacity(0.4), radius: 3, y: 0)
                    // Centred on the playhead and clamped so it never
                    // overhangs either end. Both the size and the inset
                    // derive from `thumbSize` — previously the offset was
                    // hardcoded to the 7pt thumb's geometry, so the thumb
                    // jumped sideways by 1.5pt the moment you pressed down.
                    .offset(x: max(0, min(w * ratio - thumbSize / 2, w - thumbSize)))
                    .animation(.easeOut(duration: 0.06), value: ui.isDraggingScrubber)
                }
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
            // The visible bar is 3pt tall inside an 8pt strip, which is close
            // to unhittable when you're trying to seek. Extend the drag target
            // into the free space below without changing the layout.
            .frame(height: 8)
            .contentShape(Rectangle().inset(by: -8))
            
            HStack {
                let pos = ui.isDraggingScrubber ? ui.dragRatio * media.currentTrack.duration : media.currentTrack.position(at: now)
                Text(fmt(pos))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Text.caption)
                
                Spacer()
                
                Text("-\(fmt(max(0, media.currentTrack.duration - pos)))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Text.caption)
            }
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
    
    private var accentColor: Color {
        Theme.accent(for: media.currentTrack.source)
    }
    
    private func fmt(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
