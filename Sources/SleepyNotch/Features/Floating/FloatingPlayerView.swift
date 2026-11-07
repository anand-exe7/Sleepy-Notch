import SwiftUI

/// The floating player's content, at the size the controller says.
struct FloatingPlayerView: View {
    @ObservedObject var controller: FloatingPlayerController
    @ObservedObject var media: PlaybackCoordinator
    @ObservedObject var power: PowerStateMonitor
    @ObservedObject var library: LibraryController
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var upNext: UpNextService
    @ObservedObject var preferences: HUDPreferences

    var body: some View {
        let size = controller.size
        Group {
            switch size {
            case .mini: mini
            case .player: player
            case .expanded: expanded
            }
        }
        .padding(size == .mini ? 12 : 16)
        .frame(width: size.windowSize.width, height: size.windowSize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: size == .mini ? 22 : 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size == .mini ? 22 : 30, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
        )
        .environment(\.colorScheme, .dark)
        // The scrubber and the lyric lines run while this window is on screen.
        .environment(\.notchCardActive, true)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: size)
        .onAppear { visibilityChanged() }
        .onChange(of: size) { _ in visibilityChanged() }
        .onChange(of: media.currentTrack.identityKey) { _ in
            if size == .expanded && preferences.playingNext { upNext.refresh(for: media.currentTrack) }
        }
        .onDisappear { lyrics.setVisible(false, surface: "floating") }
    }

    private func visibilityChanged() {
        lyrics.setVisible(controller.size == .expanded, surface: "floating")
        if controller.size == .expanded && preferences.playingNext { upNext.refresh(for: media.currentTrack) }
    }

    private var track: TrackInfo { media.currentTrack }
    private var title: String { track.isPlaceholder ? "Nothing playing" : track.title }
    private var subtitle: String { track.isPlaceholder ? "Start music in Music or Spotify" : track.artist }
    /// A long title is cut with "…", not scrolled: scrolling text over this
    /// window's blurred background makes the system redo the blur on every
    /// frame (4-9% CPU), and nothing here is worth that.
    private var animatesText: Bool { false }

    // MARK: - Mini

    private var mini: some View {
        HStack(spacing: 10) {
            CoverArtView(image: track.artworkImage, size: 40, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(title, font: .system(size: 13, weight: .semibold), color: Theme.Text.primary, speed: 26, animates: animatesText)
                    .frame(height: 17)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { media.togglePlayPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundColor(Theme.Text.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")
            windowButtons
        }
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                CoverArtView(image: track.artworkImage, size: 56, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(title, font: .system(size: 15, weight: .semibold), color: Theme.Text.primary, speed: 26, animates: animatesText)
                        .frame(height: 19)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                windowButtons
            }
            PlayerScrubber(media: media, power: power, accentColor: preferences.highlightColor)
            TransportControls(media: media)
                .frame(height: 36)
        }
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                windowButtons
            }
            .padding(.bottom, -6)
            CoverArtView(image: track.artworkImage, size: 150, cornerRadius: 18)
            VStack(spacing: 2) {
                MarqueeText(title, font: .system(size: 17, weight: .semibold), color: Theme.Text.primary, speed: 26, animates: animatesText, alignment: .center)
                    .frame(height: 22)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }
            PlayerScrubber(media: media, power: power, accentColor: preferences.highlightColor)
            TransportControls(media: media)
                .frame(height: 36)
            lyricsBlock
            upNextBlock
            Spacer(minLength: 0)
        }
    }

    /// The line being sung with the one before and after it.
    @ViewBuilder
    private var lyricsBlock: some View {
        if lyrics.isEnabled, lyrics.status == .found, !lyrics.lines.isEmpty {
            let current = lyrics.currentIndex ?? -1
            VStack(spacing: 3) {
                lyricLine(current - 1, dim: true)
                lyricLine(current, dim: false)
                lyricLine(current + 1, dim: true)
            }
            .frame(height: 64)
            .animation(.easeOut(duration: 0.25), value: lyrics.currentIndex)
        } else if lyrics.isEnabled, lyrics.status == .none, !track.isPlaceholder {
            Text("No synced lyrics for this song")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.tertiary)
                .frame(height: 64)
        }
    }

    private func lyricLine(_ index: Int, dim: Bool) -> some View {
        let text = lyrics.lines.indices.contains(index) ? (lyrics.lines[index].text.isEmpty ? "♪" : lyrics.lines[index].text) : " "
        return Text(text)
            .font(.system(size: dim ? 12 : 14, weight: dim ? .regular : .semibold))
            .foregroundColor(dim ? Theme.Text.tertiary : Theme.Text.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    /// Apple Music only: the next songs in what's playing.
    @ViewBuilder
    private var upNextBlock: some View {
        if preferences.playingNext && !upNext.items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing Next")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Text.secondary)
                    .padding(.bottom, 2)
                ForEach(upNext.items.prefix(5)) { item in
                    Button { upNext.play(item) } label: {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.Text.primary)
                                .lineLimit(1)
                            Text(item.artist)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.Text.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Window buttons

    /// Changes the size, and closes the window.
    private var windowButtons: some View {
        HStack(spacing: 2) {
            Button { controller.size = controller.size.next } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Change size")
            .accessibilityLabel("Change size")
            Button { controller.hide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Close")
            .accessibilityLabel("Close")
        }
    }
}
