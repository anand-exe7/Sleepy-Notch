import SwiftUI

/// Previous, play/pause, next — bare white glyphs like the system's Now
/// Playing, with the play/pause glyph larger.
struct TransportControls: View {
    @ObservedObject var media: PlaybackCoordinator

    var body: some View {
        HStack(spacing: 30) {
            TransportButton(symbol: "backward.fill", size: 16) {
                media.previousTrack()
            }
            TransportButton(
                symbol: media.currentTrack.isPlaying ? "pause.fill" : "play.fill",
                size: 24
            ) {
                media.togglePlayPause()
            }
            TransportButton(symbol: "forward.fill", size: 16) {
                media.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A transport glyph with no chrome: white, a soft circle behind it on
/// hover, and a quick squeeze when pressed.
private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white.opacity(hover.isHovered ? 1 : 0.88))
                // Swapping play/pause pops instead of snapping.
                .id(symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .frame(width: size + 16, height: size + 16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(hover.isHovered ? 0.1 : 0))
                )
                .animation(.easeOut(duration: 0.12), value: hover.isHovered)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: symbol)
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hover.isHovered = $0 }
    }
}

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class HoverState: ObservableObject {
    @Published var isHovered = false
}
