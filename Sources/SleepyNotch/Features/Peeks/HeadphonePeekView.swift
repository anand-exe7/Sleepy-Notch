import SwiftUI

/// Headphones connecting or disconnecting.
///
/// For AirPods it plays the moment you know from the real thing: the charging
/// case appears, then the left and right earbuds lift out of it one after the
/// other, turning to face you as they settle. Disconnecting puts them back.
/// Over-ear models turn in as a single piece. One short animation, then still.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = HeadphoneMotion()

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 52, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Text.secondary)
            }

            Spacer(minLength: 8)

            if let battery = event.battery {
                HeadphoneBatteryView(battery: battery)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .onAppear(perform: animate)
    }

    // MARK: - Artwork

    @ViewBuilder private var artwork: some View {
        if let symbols = event.model.budSymbols {
            ZStack {
                Image(systemName: symbols.chargingCase)
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white)
                    .scaleEffect(motion.caseShown ? 1 : 0.85, anchor: .bottom)
                    .opacity(motion.caseShown ? (event.isConnected ? 1 : 0.5) : 0)
                    .offset(y: 11)
                bud(symbols.left, side: -1, isOut: motion.leftOut)
                bud(symbols.right, side: 1, isOut: motion.rightOut)
            }
        } else {
            Image(systemName: event.model.symbolName)
                .font(.system(size: 27, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white)
                .rotation3DEffect(.degrees(motion.leftOut ? 0 : 35), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .scaleEffect(motion.leftOut ? 1 : 0.8)
                .opacity(motion.leftOut ? (event.isConnected ? 1 : 0.45) : 0)
        }
    }

    /// An earbud resting in the case (`isOut == false`: small, hidden, at the
    /// case opening) or lifted out beside its pair, facing forward.
    private func bud(_ symbol: String, side: CGFloat, isOut: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.white)
            .rotation3DEffect(.degrees(isOut ? 0 : Double(side) * 55), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(isOut ? 1 : 0.55)
            .offset(x: isOut ? side * 8 : 0, y: isOut ? -8 : 8)
            .opacity(isOut ? 1 : 0)
    }

    // MARK: - Motion

    private func animate() {
        if event.isConnected {
            guard !reduceMotion else {
                motion.caseShown = true
                motion.leftOut = true
                motion.rightOut = true
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                motion.caseShown = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.2)) {
                motion.leftOut = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.3)) {
                motion.rightOut = true
            }
        } else {
            // Start out of the case, then put them away.
            motion.caseShown = true
            motion.leftOut = true
            motion.rightOut = true
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.3).delay(0.25)) {
                    motion.leftOut = false
                }
                withAnimation(.easeIn(duration: 0.3).delay(0.32)) {
                    motion.rightOut = false
                }
            }
        }
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class HeadphoneMotion: ObservableObject {
    @Published var caseShown = false
    @Published var leftOut = false
    @Published var rightOut = false
}

/// Small rings for left / right / case, or a single ring for over-ear.
/// White like the system battery widget; orange only when low.
private struct HeadphoneBatteryView: View {
    let battery: HeadphoneBattery

    var body: some View {
        HStack(spacing: 8) {
            if let main = battery.main {
                gauge("Battery", main)
            } else {
                if let left = battery.left { gauge("L", left) }
                if let right = battery.right { gauge("R", right) }
                if let caseLevel = battery.caseLevel { gauge("Case", caseLevel) }
            }
        }
    }

    private func gauge(_ label: String, _ level: Int) -> some View {
        let color = level <= 20 ? Theme.Status.warning : Theme.Text.primary
        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: Double(level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
            }
            .frame(width: 22, height: 22)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Text.tertiary)
        }
    }
}

extension HeadphoneModel {
    /// Separate left / right earbud and charging-case symbols, for the
    /// lift-out animation. `nil` for over-ear models, or if this macOS lacks
    /// any of the three.
    var budSymbols: (left: String, right: String, chargingCase: String)? {
        let names: [String]
        switch self {
        case .airPods:
            names = ["airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill"]
        case .airPodsPro:
            names = ["airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless.fill"]
        case .airPodsMax, .beats, .headphones:
            return nil
        }
        guard names.allSatisfy(Self.symbolExists) else { return nil }
        return (names[0], names[1], names[2])
    }

    /// The single symbol for this model, falling back to generic headphones.
    var symbolName: String {
        let preferred: String
        switch self {
        case .airPods: preferred = "airpods.gen3"
        case .airPodsPro: preferred = "airpodspro"
        case .airPodsMax: preferred = "airpodsmax"
        case .beats: preferred = "beats.headphones"
        case .headphones: preferred = "headphones"
        }
        return Self.symbolExists(preferred) ? preferred : "headphones"
    }

    private static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
