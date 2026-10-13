import SwiftUI

/// The headphones' battery, like the Batteries widget: a ring and the
/// percentage, both filling up from empty as it appears. Earbuds show the
/// lower of the two — the one that runs out first — with the case beneath
/// when macOS reports it. Orange at 20% and under.
struct HeadphoneBatteryView: View {
    let battery: HeadphoneBattery

    @StateObject private var fill = BatteryFill()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Int? {
        battery.main ?? [battery.left, battery.right].compactMap { $0 }.min()
    }

    var body: some View {
        if let level {
            let tint = level <= 20 ? Theme.Status.warning : Theme.Text.primary
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: fill.fraction)
                            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 19, height: 19)

                    CountingPercent(value: fill.fraction * 100)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                }

                if battery.main == nil, let caseLevel = battery.caseLevel {
                    Text("Case \(caseLevel)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .fixedSize()
            .onAppear {
                let target = Double(level) / 100
                guard !reduceMotion else {
                    fill.fraction = target
                    return
                }
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.15)) {
                    fill.fraction = target
                }
            }
        }
    }
}

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class BatteryFill: ObservableObject {
    @Published var fraction: Double = 0
}
