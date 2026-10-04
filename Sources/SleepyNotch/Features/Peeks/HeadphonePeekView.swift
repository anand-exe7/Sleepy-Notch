import SwiftUI

/// Headphones connecting or disconnecting. On connect the icon spins in
/// once in 3D, like the iPhone pairing card; battery rings appear if macOS
/// reports levels.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    static let tint = Theme.Status.device

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var intro = SpinIntro()

    private var spun: Bool { intro.spun }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: event.model.symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(Theme.Text.primary)
                .rotation3DEffect(.degrees(spun ? 0 : -360), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .scaleEffect(spun ? 1 : 0.55)
                .opacity(event.isConnected ? 1 : 0.45)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Self.tint)
                        .blur(radius: 12)
                        .opacity(event.isConnected ? 0.3 : 0)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(event.isConnected ? Self.tint : Theme.Text.secondary)
            }

            Spacer(minLength: 8)

            if let battery = event.battery {
                HeadphoneBatteryView(battery: battery)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            guard event.isConnected, !reduceMotion else {
                intro.spun = true
                return
            }
            withAnimation(.spring(response: 1.0, dampingFraction: 0.72)) {
                intro.spun = true
            }
        }
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class SpinIntro: ObservableObject {
    @Published var spun = false
}

/// Small rings for left / right / case, or a single ring for over-ear.
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
        let color = level <= 20 ? Theme.Status.warning : Theme.Status.charging
        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 2.5)
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
                .foregroundColor(Theme.Text.secondary)
        }
    }
}

extension HeadphoneModel {
    /// The matching SF Symbol, falling back to generic headphones on systems
    /// whose symbol set doesn't have it.
    var symbolName: String {
        let preferred: String
        switch self {
        case .airPods: preferred = "airpods"
        case .airPodsPro: preferred = "airpodspro"
        case .airPodsMax: preferred = "airpodsmax"
        case .beats: preferred = "beats.headphones"
        case .headphones: preferred = "headphones"
        }
        return NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
            ? preferred
            : "headphones"
    }
}
