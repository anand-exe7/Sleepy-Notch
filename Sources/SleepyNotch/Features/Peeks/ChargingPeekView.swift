import SwiftUI

/// Plug in, unplug, full, low. Uses the system's green and orange, with no
/// glow, so it reads like the battery status macOS itself shows.
///
/// The intro is choreographed on an `IntroClock` (see `ChargingPeekScene`).
/// While charging, the liquid keeps rippling for as long as the peek is up;
/// otherwise the clock stops as soon as the intro settles.
struct ChargingPeekView: View {
    let event: PowerEvent
    let style: ChargingPeekStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var clock = IntroClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.isRunning)) { timeline in
            ChargingPeekScene(event: event, style: style, t: clock.time(at: timeline.date))
        }
        .onAppear {
            if reduceMotion {
                clock.finish()
            } else {
                // Charging: ripple until the peek folds away.
                clock.run(until: event.kind == .pluggedIn ? PeekContent.power(event).duration : 1.8)
            }
        }
    }
}

/// The charging peek at one moment of its intro, `t` seconds in — a pure
/// function of time, so any frame can be drawn on its own.
///
/// The battery pops in and the words slide in beside it. Plugging in, the
/// liquid pours in from empty, sloshing as it rises and calming once it's
/// level, while the number counts up with it; the bolt strikes in with a
/// twist, and the number gives a kick as the fill lands. Low battery pulses
/// the battery three times; fully charged pops a checkmark.
struct ChargingPeekScene: View {
    let event: PowerEvent
    let style: ChargingPeekStyle
    let t: Double

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

    private static let fillStart: Double = 0.25
    private static let fillDuration: Double = 1.1

    private var tint: Color { Self.tint(for: event) }
    private var isCharging: Bool { event.kind == .pluggedIn || event.kind == .fullyCharged }

    /// 0…1 of the battery's level shown so far. Charging pours in from
    /// empty; the other states settle quickly to their level.
    private var fill: Double {
        let level = Double(event.level) / 100
        if event.kind == .pluggedIn {
            return level * IntroCurve.easeOut(t, start: Self.fillStart, duration: Self.fillDuration)
        }
        return level * IntroCurve.spring(t, start: 0.15, response: 0.5, damping: 0.85)
    }

    var body: some View {
        let pop = IntroCurve.spring(t, start: 0.08, response: 0.45, damping: 0.55)
        let words = IntroCurve.spring(t, start: 0.14, response: 0.5, damping: 0.8)
        let landing = IntroCurve.bump(t, start: Self.fillStart + Self.fillDuration - 0.2, duration: 0.32)

        HStack(spacing: 14) {
            indicator
                .frame(width: 44, height: 44)
                .scaleEffect((0.4 + 0.6 * pop) * (1 + lowPulse))
                .opacity(IntroCurve.linear(t, start: 0.08, duration: 0.12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }
            .offset(x: (1 - words) * -10)
            .opacity(IntroCurve.easeOut(t, start: 0.14, duration: 0.3))

            Spacer(minLength: 8)

            CountingPercent(value: fill * 100)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(tint)
                .scaleEffect(1 + (event.kind == .pluggedIn ? 0.12 * landing : 0), anchor: .trailing)
                .opacity(IntroCurve.easeOut(t, start: 0.18, duration: 0.25))
        }
        .padding(.horizontal, 20)
    }

    /// Low battery: three gentle beats, then still.
    private var lowPulse: Double {
        guard event.kind == .low else { return 0 }
        return 0.07 * IntroCurve.bump(t, start: 0.4, duration: 0.3)
            + 0.07 * IntroCurve.bump(t, start: 0.75, duration: 0.3)
            + 0.07 * IntroCurve.bump(t, start: 1.1, duration: 0.3)
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
        ZStack {
            if style == .ring && isCharging {
                ChargingRing(fraction: fill, tint: tint)
            } else {
                LiquidBattery(fraction: fill, tint: tint, phase: t * 5, amplitude: slosh)
            }
            if isCharging {
                symbol
            }
        }
    }

    /// The liquid sloshes while it pours in and calms to a gentle ripple
    /// once it's level. Still when not charging.
    private var slosh: Double {
        guard event.kind == .pluggedIn, t < 100 else { return 0 }
        let since = max(0, t - Self.fillStart)
        return 1.2 + 2.6 * exp(-since * 1.8)
    }

    /// The bolt strikes in with a twist; the checkmark pops.
    private var symbol: some View {
        let strike = IntroCurve.spring(t, start: 0.35, response: 0.42, damping: 0.45)
        return Image(systemName: event.kind == .fullyCharged ? "checkmark" : "bolt.fill")
            .font(.system(size: style == .ring ? 15 : 14, weight: .bold))
            .foregroundColor(style == .ring ? tint : .white)
            .shadow(color: .black.opacity(style == .ring ? 0 : 0.25), radius: 1, y: 0.5)
            .scaleEffect(0.2 + 0.8 * strike)
            .rotationEffect(.degrees((1 - strike) * -35))
            .opacity(IntroCurve.linear(t, start: 0.35, duration: 0.1))
            .offset(y: style == .liquid ? 2 : 0)
    }
}
