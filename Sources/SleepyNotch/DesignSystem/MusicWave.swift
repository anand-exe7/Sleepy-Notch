import SwiftUI

/// Siri-style lines that ripple along the bottom of the open card while a
/// song plays, and settle into one still line when it's paused.
///
/// Decorative only: no audio is captured. The "energy" that swells and
/// relaxes is a blend of slow, unrelated sine waves, which reads as music
/// without needing microphone or system-audio access.
///
/// Battery: it exists only inside the open card, and its timeline runs only
/// while `isActive` (playing, notch visible, motion allowed). Paused, it
/// draws one frame and stops.
struct MusicWave: View {
    let isActive: Bool
    var color: Color = .white

    /// Back-to-front: fainter, calmer lines behind one bright line.
    private static let lines: [(opacity: Double, amplitude: Double, phaseOffset: Double, width: CGFloat)] = [
        (0.18, 0.55, 2.1, 1),
        (0.32, 0.8, 1.0, 1),
        (0.9, 1.0, 0.0, 1.6),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let energy = isActive ? Self.energy(at: time) : 0
            Canvas { context, size in
                for line in Self.lines {
                    let path = Self.path(
                        in: size,
                        amplitude: line.amplitude * energy,
                        phase: time * 5 + line.phaseOffset
                    )
                    context.stroke(path, with: .color(color.opacity(line.opacity)), lineWidth: line.width)
                }
            }
        }
        // Fade out at both ends, like Siri's waveform.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.2),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.easeOut(duration: 0.4), value: isActive)
    }

    /// 0.25…1: a slow swell with faster flutters on top.
    private static func energy(at time: Double) -> Double {
        let swell = 0.55 + 0.25 * sin(time * 1.3) + 0.12 * sin(time * 3.1 + 0.7) + 0.08 * sin(time * 7.7 + 1.9)
        return min(1, max(0.25, swell))
    }

    /// One sine line whose height tapers to zero at both ends, so the ripple
    /// lives in the middle of the card.
    private static func path(in size: CGSize, amplitude: Double, phase: Double) -> Path {
        let midY = size.height / 2
        let maxHeight = Double(size.height / 2) * 0.9
        var path = Path()
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= size.width {
            let progress = Double(x / size.width)          // 0…1
            let centered = progress * 2 - 1                 // -1…1
            let taper = max(0, 1 - centered * centered)     // 0 at ends, 1 mid
            let y = midY + CGFloat(sin(progress * .pi * 2 * 2.2 + phase) * amplitude * maxHeight * taper)
            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            x += step
        }
        return path
    }
}
