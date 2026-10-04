import SwiftUI

/// Plug in, unplug, full, low. Plugging in fills a gauge up to the real
/// battery level while the percentage counts up with it, a bolt zaps in, and
/// a glow pulses a few times. Everything finishes within the peek; the
/// liquid's wave exists only while this view is on screen.
struct ChargingPeekView: View {
    let event: PowerEvent
    let style: ChargingPeekStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var intro = ChargingIntro()

    private var filled: Bool { intro.filled }
    private var symbolIn: Bool { intro.symbolIn }
    private var pulse: Bool { intro.pulse }

    static func tint(for event: PowerEvent) -> Color {
        switch event.kind {
        case .pluggedIn, .fullyCharged:
            return Theme.Status.charging
        case .low:
            return Theme.Status.warning
        case .unplugged:
            return event.level <= PowerSourceMonitor.lowThreshold ? Theme.Status.warning : Theme.Text.primary
        }
    }

    private var tint: Color { Self.tint(for: event) }
    private var fraction: Double { Double(event.level) / 100 }
    private var isCharging: Bool { event.kind == .pluggedIn || event.kind == .fullyCharged }

    var body: some View {
        HStack(spacing: 14) {
            indicator
                .frame(width: 44, height: 44)
                .background(glow)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            CountingPercent(value: isCharging && !filled ? 0 : Double(event.level))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 20)
        .onAppear(perform: animateIn)
    }

    // MARK: - Copy

    private var title: String {
        switch event.kind {
        case .pluggedIn: return "Charging"
        case .fullyCharged: return "Fully Charged"
        case .unplugged: return "On Battery"
        case .low: return "Low Battery"
        }
    }

    private var subtitle: String {
        switch event.kind {
        case .pluggedIn:
            // Optimized Battery Charging can hold at ~80% while plugged in.
            return event.isCharging ? "Power adapter connected" : "Connected · charging on hold"
        case .fullyCharged: return "Unplug any time"
        case .unplugged: return "Power adapter removed"
        case .low: return "Plug in soon"
        }
    }

    // MARK: - Indicator

    @ViewBuilder private var indicator: some View {
        if isCharging {
            ZStack {
                switch style {
                case .ring:
                    ChargingRing(fraction: filled ? fraction : 0, tint: tint)
                case .liquid:
                    LiquidBattery(fraction: filled ? fraction : 0, tint: tint, waves: !reduceMotion)
                }
                Image(systemName: event.kind == .fullyCharged ? "checkmark" : "bolt.fill")
                    .font(.system(size: style == .ring ? 16 : 14, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: tint, radius: symbolIn ? 6 : 0)
                    .scaleEffect(symbolIn ? 1 : 0.2)
                    .rotationEffect(.degrees(symbolIn ? 0 : -25))
                    .opacity(symbolIn ? 1 : 0)
                    .offset(y: style == .liquid ? 2 : 0)
            }
        } else {
            Image(systemName: Self.batterySymbol(for: event.level))
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(tint)
                .scaleEffect(event.kind == .low && pulse ? 1.08 : 1)
        }
    }

    private var glow: some View {
        Circle()
            .fill(tint)
            .blur(radius: 12)
            .opacity(pulse ? 0.45 : (event.kind == .unplugged ? 0.06 : 0.12))
            .scaleEffect(pulse ? 1.15 : 0.9)
    }

    private func animateIn() {
        guard !reduceMotion else {
            intro.filled = true
            intro.symbolIn = true
            return
        }
        withAnimation(.easeOut(duration: 1.1).delay(0.15)) {
            intro.filled = true
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.45).delay(0.1)) {
            intro.symbolIn = true
        }
        if event.kind == .pluggedIn || event.kind == .low {
            // An odd count so it settles on the glowing state, not mid-pulse.
            withAnimation(.easeInOut(duration: 0.7).repeatCount(3, autoreverses: true).delay(0.2)) {
                intro.pulse = true
            }
        }
    }

    static func batterySymbol(for level: Int) -> String {
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

/// View-local animation flags. Kept in an `ObservableObject` rather than
/// `@State`, which this toolchain resolves to a macro whose plugin ships only
/// with Xcode — the same reason `NotchInteractionState` exists.
private final class ChargingIntro: ObservableObject {
    @Published var filled = false
    @Published var symbolIn = false
    @Published var pulse = false
}

/// iPhone-style ring that fills clockwise from the top.
private struct ChargingRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .bottom, endPoint: .top),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(3)
    }
}

/// An upright battery filling with liquid. The surface ripples only while
/// the peek is up; with Reduce Motion it's a flat fill.
private struct LiquidBattery: View {
    let fraction: Double
    let tint: Color
    let waves: Bool

    private var fill: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .bottom, endPoint: .top)
    }

    var body: some View {
        VStack(spacing: 1.5) {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 9, height: 3)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                liquid
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.2)
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
private struct CountingPercent: View, Animatable {
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
