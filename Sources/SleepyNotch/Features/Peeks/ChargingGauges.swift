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

/// An upright battery filling with liquid. The surface ripples only while
/// the peek is up; with Reduce Motion it's a flat fill.
struct LiquidBattery: View {
    let fraction: Double
    let tint: Color
    let waves: Bool

    private var fill: Color { tint }

    var body: some View {
        VStack(spacing: 1.5) {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 9, height: 3)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                liquid
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
            }
            .frame(width: 24, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder private var liquid: some View {
        if waves {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                LiquidShape(fraction: fraction, phase: timeline.date.timeIntervalSinceReferenceDate * 4)
                    .fill(fill)
            }
        } else {
            LiquidShape(fraction: fraction, phase: 0)
                .fill(fill)
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
        let amplitude: CGFloat = fraction <= 0.02 || fraction >= 0.98 ? 0 : 1.8
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
