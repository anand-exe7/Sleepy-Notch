import SwiftUI

/// A few still bars beside the mini cover: raised while a song plays, flat
/// while it's paused. They never move — the collapsed notch doesn't animate
/// — so showing them costs nothing.
struct WaveformVisualizer: View {
    let isPlaying: Bool
    var tintColor: Color
    var barCount: Int = 4
    var height: CGFloat = 14

    /// Fixed heights, as fractions of `height`, so the bars read as a
    /// waveform rather than a level meter.
    private static let levels: [CGFloat] = [0.5, 1.0, 0.5, 0.9, 0.9, 0.8]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(LinearGradient(
                        colors: [tintColor.opacity(0.6), tintColor],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(width: 2, height: barHeight(i))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.2), value: isPlaying)
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard isPlaying else { return 2.5 }
        return height * 0.85 * Self.levels[index % Self.levels.count] + 2.5
    }
}
