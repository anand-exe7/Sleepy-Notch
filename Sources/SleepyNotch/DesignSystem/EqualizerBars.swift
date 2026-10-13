import SwiftUI

/// Four bars that dance beside the title while a song plays, like the Dynamic
/// Island's, and settle into a row of dots when it's paused.
///
/// Decorative only: no audio is captured. Each bar's level is a blend of slow,
/// unrelated sine waves, which reads as music without needing microphone or
/// system-audio access.
///
/// Battery: it lives only inside the open card, and its timeline runs only
/// while a song plays and motion is welcome (`animates`), at 30 fps. Paused,
/// it draws one frame and stops.
struct EqualizerBars: View {
    let isPlaying: Bool
    /// False under Low Power Mode or Reduce Motion: the bars hold still,
    /// raised while playing.
    let animates: Bool
    var color: Color = .white

    private static let barCount = 4
    private static let barWidth: CGFloat = 3
    /// Per bar: two frequencies and a phase, chosen not to line up.
    private static let voices: [(f1: Double, f2: Double, phase: Double)] = [
        (5.1, 8.3, 0.0),
        (6.7, 3.9, 1.7),
        (4.3, 9.1, 3.1),
        (7.9, 5.3, 4.6),
    ]
    /// Still heights for playing without motion: a gentle arch.
    private static let restingLevels: [Double] = [0.45, 0.8, 0.65, 0.35]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(isPlaying && animates))) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: (geo.size.width - Self.barWidth * CGFloat(Self.barCount)) / CGFloat(Self.barCount - 1)) {
                    ForEach(0..<Self.barCount, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(
                                width: Self.barWidth,
                                height: max(Self.barWidth, geo.size.height * level(index, at: time))
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Playing ↔ paused springs the bars up or down; the per-frame dance
        // itself isn't animated (each frame is already where it should be).
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPlaying)
        .accessibilityHidden(true)
    }

    /// 0…1 for one bar at `time`.
    private func level(_ index: Int, at time: Double) -> Double {
        guard isPlaying else { return 0 }
        guard animates else { return Self.restingLevels[index] }
        let voice = Self.voices[index]
        let mix = 0.6 * sin(time * voice.f1 + voice.phase) + 0.4 * sin(time * voice.f2 + voice.phase * 1.3)
        return 0.28 + 0.72 * abs(mix)
    }
}
