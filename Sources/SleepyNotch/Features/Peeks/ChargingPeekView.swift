import SwiftUI
import AppKit

/// Plug in, unplug, full, low, laid out like the headphone card: the status
/// in one line under the notch, and below it a large battery with the level
/// beside it in big numbers. The system's own green, orange and red, no glow.
///
/// It plays once, calmly: the battery rises from below on the same
/// fast-then-gentle curve as AirPods Pro and settles into place, the text
/// follows, and then the battery tells its story:
/// - **Plugged in:** the charge fills to the level while the number counts
///   up, then the bolt fades in.
/// - **Unplugged:** the bolt fades away and the charge turns white (orange
///   when low).
/// - **Fully charged:** green to the top, and a check appears.
/// - **Low battery:** orange (red under 10%), with one slow breath.
///
/// Every step is a one-shot animation started by a one-shot timer; nothing
/// runs once it has settled.
struct ChargingPeekView: View {
    let event: PowerEvent

    @StateObject private var reveal = ChargingReveal()

    /// The height the peek drops below the notch.
    static let contentHeight: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            titleRow
                .padding(.top, 16)

            Spacer(minLength: 0)

            hero
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reveal.run(for: event) }
        .onDisappear { reveal.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(event.level) percent. \(subtitle)")
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .opacity(reveal.text ? 1 : 0)
        .offset(y: reveal.text ? 0 : 4)
    }

    private var title: String {
        switch event.kind {
        case .pluggedIn: return event.isCharging ? "Charging" : "Plugged In"
        case .fullyCharged: return "Fully Charged"
        case .unplugged: return "On Battery"
        case .low: return "Low Battery"
        }
    }

    private var subtitle: String {
        switch event.kind {
        case .pluggedIn:
            // Optimized Battery Charging can hold the charge while plugged in.
            return event.isCharging ? "Power adapter connected" : "Charging on hold"
        case .fullyCharged: return "You can unplug any time"
        case .unplugged: return "Power adapter disconnected"
        case .low: return "Plug in soon"
        }
    }

    // MARK: - Battery and level

    private var hero: some View {
        HStack(spacing: 18) {
            ZStack {
                BatteryGlyph(
                    fraction: reveal.fill,
                    tint: chargeTint,
                    chargeOpacity: reveal.breath ? 0.4 : 1
                )
                glyph
                    // Centred on the body, not on the body and terminal.
                    .offset(x: -2.75)
            }

            CountingPercent(value: reveal.count)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(numberTint)
                .frame(minWidth: 82, alignment: .leading)
                .opacity(reveal.text ? 1 : 0)
        }
        // Rises from below, slightly large, and settles into place.
        .scaleEffect(reveal.risen ? 1 : 1.18)
        .offset(y: reveal.risen ? 0 : 90)
    }

    /// The bolt while charging, a check when full; the bolt also shows at
    /// the start of an unplug, and fades away.
    @ViewBuilder private var glyph: some View {
        switch event.kind {
        case .pluggedIn, .unplugged:
            Image(systemName: event.isCharging || event.kind == .unplugged ? "bolt.fill" : "powerplug.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                .scaleEffect(reveal.glyph ? 1 : 0.6)
                .opacity(reveal.glyph ? 1 : 0)
        case .fullyCharged:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                .scaleEffect(reveal.glyph ? 1 : 0.6)
                .opacity(reveal.glyph ? 1 : 0)
        case .low:
            EmptyView()
        }
    }

    /// Green while it's charging or full; white on battery, warning colours
    /// when low. An unplug starts green and turns white as the bolt leaves.
    private var chargeTint: Color {
        let lowTint = event.level <= 10 ? Theme.Status.critical : Theme.Status.warning
        switch event.kind {
        case .pluggedIn, .fullyCharged: return Theme.Status.charging
        case .low: return lowTint
        case .unplugged:
            if reveal.glyph { return Theme.Status.charging }
            return event.level <= PowerSourceMonitor.lowThreshold ? lowTint : .white
        }
    }

    private var numberTint: Color {
        switch event.kind {
        case .low: return event.level <= 10 ? Theme.Status.critical : Theme.Status.warning
        default: return Theme.Text.primary
        }
    }
}

/// Which beats of the charging card have played. A small object rather than
/// `@State`, which this toolchain can't build (see `NotchInteractionState`).
@MainActor
final class ChargingReveal: ObservableObject {
    @Published var risen = false
    @Published var text = false
    /// 0…1 of the charge shown.
    @Published var fill: Double = 0
    /// The level the number shows, counting.
    @Published var count: Double = 0
    @Published var glyph = false
    @Published var breath = false

    private var steps: [DispatchWorkItem] = []

    /// The battery's rise: almost all the way at once, then a long, gentle
    /// glide to a stop, like the iPhone's pop-up.
    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.85)
    private static let calm = Animation.easeOut(duration: 0.45)

    func run(for event: PowerEvent) {
        cancel()
        let level = Double(event.level) / 100

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            risen = true; text = true; fill = level; count = Double(event.level)
            glyph = event.kind == .pluggedIn || event.kind == .fullyCharged
            return
        }

        // Unplugging and full start where things were: the charge already
        // in, the bolt still on.
        var start = Transaction()
        start.disablesAnimations = true
        withTransaction(start) {
            switch event.kind {
            case .pluggedIn:
                fill = 0; count = 0
            case .fullyCharged:
                fill = max(0, level - 0.08); count = Double(event.level)
            case .unplugged:
                fill = level; count = Double(event.level); glyph = true
            case .low:
                fill = level; count = Double(event.level)
            }
        }

        step(at: 0.06, Self.rise) { $0.risen = true }
        step(at: 0.3, Self.calm) { $0.text = true }

        switch event.kind {
        case .pluggedIn:
            // The charge fills to the level as the number counts up; then
            // the bolt.
            step(at: 0.35, .easeOut(duration: 1.1)) {
                $0.fill = level
                $0.count = Double(event.level)
            }
            step(at: 1.25, .spring(response: 0.45, dampingFraction: 0.9)) { $0.glyph = true }
        case .fullyCharged:
            step(at: 0.35, .easeOut(duration: 0.7)) { $0.fill = 1 }
            step(at: 0.95, .spring(response: 0.45, dampingFraction: 0.9)) { $0.glyph = true }
        case .unplugged:
            // The bolt leaves, and the green with it.
            step(at: 0.85, .easeInOut(duration: 0.6)) { $0.glyph = false }
        case .low:
            // One slow breath of the charge.
            step(at: 0.9, .easeInOut(duration: 0.6)) { $0.breath = true }
            step(at: 1.5, .easeInOut(duration: 0.7)) { $0.breath = false }
        }
    }

    func cancel() {
        steps.forEach { $0.cancel() }
        steps.removeAll()
    }

    private func step(at time: TimeInterval, _ animation: Animation, _ change: @escaping (ChargingReveal) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(animation) { change(self) }
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
    }
}
