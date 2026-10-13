import SwiftUI

/// iPhone-style ring that fills clockwise from the top.
struct ChargingRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(3)
    }
}

/// An upright battery drawn like the system's own glyph — an outline, a
/// small cap, and the charge inset from the outline rather than touching it.
/// The charge is liquid: while `waves` is on its surface ripples (only while
/// the peek is up); otherwise, and with Reduce Motion, it's a flat fill.
struct LiquidBattery: View {
    let fraction: Double
    let tint: Color
    let waves: Bool

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
                liquid
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .padding(Self.inset)
            }
            .frame(width: Self.width, height: Self.height)
        }
    }

    @ViewBuilder private var liquid: some View {
        if waves {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                LiquidShape(fraction: fraction, phase: timeline.date.timeIntervalSinceReferenceDate * 4)
                    .fill(tint)
            }
        } else {
            LiquidShape(fraction: fraction, phase: 0)
                .fill(tint)
        }
    }
}

private struct LiquidShape: Shape {
    var fraction: Double
    var phase: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let surface = rect.maxY - rect.height * CGFloat(fraction)
        // No ripple when empty or brim-full, where it would poke outside.
        let amplitude: CGFloat = fraction <= 0.02 || fraction >= 0.98 || phase == 0 ? 0 : 1.4
        let steps = 24

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(progress)
            let y = surface + CGFloat(sin(progress * 2 * .pi * 1.1 + phase)) * amplitude
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
