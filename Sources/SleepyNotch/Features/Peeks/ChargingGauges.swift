import SwiftUI

/// An upright battery drawn like the system's own glyph — an outline, a
/// small cap, and the charge inset from the outline rather than touching it.
/// The charge is liquid: its surface is a sine wave at `phase`, `amplitude`
/// points high (0 for a flat fill). The caller drives both, so the battery
/// draws one still frame per call.
struct LiquidBattery: View {
    let fraction: Double
    let tint: Color
    var phase: Double = 0
    var amplitude: Double = 0

    private static let width: CGFloat = 26
    private static let height: CGFloat = 40
    private static let inset: CGFloat = 3

    var body: some View {
        VStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(Color.white.opacity(0.45))
                .frame(width: 9, height: 2.5)
            ZStack {
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                LiquidShape(fraction: fraction, phase: phase, amplitude: amplitude)
                    .fill(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .padding(Self.inset)
            }
            .frame(width: Self.width, height: Self.height)
        }
    }
}

private struct LiquidShape: Shape {
    var fraction: Double
    var phase: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        let surface = rect.maxY - rect.height * CGFloat(fraction)
        // No ripple when empty or brim-full, where it would poke outside.
        let height = fraction <= 0.02 || fraction >= 0.98 ? 0 : CGFloat(amplitude)
        let steps = 24

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(progress)
            let y = surface + CGFloat(sin(progress * 2 * .pi * 1.1 + phase)) * height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A percentage that counts through the intermediate numbers when animated.
struct CountingPercent: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
            .monospacedDigit()
    }
}
