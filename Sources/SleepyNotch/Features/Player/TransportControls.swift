import SwiftUI

/// Previous, play/pause, next — bare white glyphs like the system's Now
/// Playing, with the play/pause glyph larger.
struct TransportControls: View {
    @ObservedObject var media: PlaybackCoordinator

    var body: some View {
        HStack(spacing: 34) {
            TransportButton(symbol: "backward.fill", size: 17, nudge: -1) {
                media.previousTrack()
            }
            TransportButton(
                symbol: media.currentTrack.isPlaying ? "pause.fill" : "play.fill",
                size: 26
            ) {
                media.togglePlayPause()
            }
            TransportButton(symbol: "forward.fill", size: 17, nudge: 1) {
                media.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A transport glyph with no chrome, like the system's Now Playing: on hover
/// it brightens and grows a touch, pressed it squeezes. No circle or
/// background behind it. Skip buttons also jump a few points the way they
/// point; play/pause morphs between its two glyphs.
private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    /// -1 or 1 for previous / next, 0 for no nudge.
    var nudge: CGFloat = 0
    let action: () -> Void

    @StateObject private var state = TransportButtonState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            playNudge()
            action()
        } label: {
            glyph
                .scaleEffect(state.isHovered ? 1.12 : 1)
                .offset(x: state.offset)
                // A generous, even hit target for every button, without
                // drawing anything there.
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.28, dampingFraction: 0.62), value: state.isHovered)
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { state.isHovered = $0 }
    }

    @ViewBuilder
    private var glyph: some View {
        let image = Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(.white.opacity(state.isHovered ? 1 : 0.82))

        if #available(macOS 14.0, *), !reduceMotion {
            // The system's own morph between play and pause.
            image
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: symbol)
        } else {
            image
                .id(symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: symbol)
        }
    }

    private func playNudge() {
        guard nudge != 0, !reduceMotion else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) {
            state.offset = nudge * 6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                state.offset = 0
            }
        }
    }
}

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class TransportButtonState: ObservableObject {
    @Published var isHovered = false
    @Published var offset: CGFloat = 0
}
