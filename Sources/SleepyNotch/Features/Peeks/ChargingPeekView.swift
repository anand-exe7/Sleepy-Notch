import SwiftUI

/// Plug in, unplug, full, low. Plugging in fills a gauge up to the real
/// battery level while the percentage counts up with it, and a bolt pops in.
/// Uses the system's green and orange, with no glow, so it reads like the
/// battery status macOS itself shows. Everything finishes within the peek;
/// the liquid's wave exists only while this view is on screen.
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            CountingPercent(value: isCharging && !filled ? 0 : Double(event.level))
                .font(.system(size: 22, weight: .semibold))
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
                    .font(.system(size: style == .ring ? 15 : 14, weight: .bold))
                    .foregroundColor(style == .ring ? tint : .white)
                    .shadow(color: .black.opacity(style == .ring ? 0 : 0.25), radius: 1, y: 0.5)
                    .scaleEffect(symbolIn ? 1 : 0.3)
                    .rotationEffect(.degrees(symbolIn ? 0 : -25))
                    .opacity(symbolIn ? 1 : 0)
                    .offset(y: style == .liquid ? 2 : 0)
            }
        } else {
            // The same battery as charging, still and without the bolt, so
            // every power peek speaks one visual language.
            LiquidBattery(fraction: filled ? fraction : 0, tint: tint, waves: false)
                .scaleEffect(event.kind == .low && pulse ? 1.06 : 1)
        }
    }

    private func animateIn() {
        guard !reduceMotion else {
            intro.filled = true
            intro.symbolIn = true
            return
        }
        // Charging fills from empty while the number counts up with it; the
        // other states settle to their level quickly.
        withAnimation(isCharging ? .easeOut(duration: 1.1).delay(0.15) : .spring(response: 0.5, dampingFraction: 0.85).delay(0.1)) {
            intro.filled = true
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.25)) {
            intro.symbolIn = true
        }
        if event.kind == .low {
            // A gentle nudge, three times. Odd so it settles enlarged-then-back.
            withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true).delay(0.2)) {
                intro.pulse = true
            }
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
