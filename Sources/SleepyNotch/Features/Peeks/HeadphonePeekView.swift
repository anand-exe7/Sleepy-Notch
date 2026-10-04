import SwiftUI

/// Headphones connecting or disconnecting, shown with Apple's real product
/// renders (see `ProductImages`).
///
/// AirPods: the charging case rises into view, then the left and right
/// earbuds lift out of it one after the other and settle side by side,
/// floating gently while the peek is up — the moment you know from the iPhone.
/// Disconnecting puts them back in the case. Over-ear models rise in as one
/// piece. If the renders aren't available, SF Symbols stand in.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = HeadphoneMotion()

    var body: some View {
        HStack(spacing: 12) {
            stage
                .frame(width: 66, height: 74)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12))
                    .foregroundColor(event.isConnected ? Theme.Text.secondary : Theme.Text.tertiary)
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

    // MARK: - Stage

    /// Floats only while connected and motion is welcome, and only as long as
    /// this peek is on screen.
    private var floats: Bool {
        event.isConnected && !reduceMotion
    }

    @ViewBuilder private var stage: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !floats)) { timeline in
            let bob = floats ? sin(timeline.date.timeIntervalSinceReferenceDate * 2.6) * 1.4 : 0
            if let set = ProductImages.earbuds(for: event.model) {
                earbuds(set, bob: bob)
            } else {
                single(bob: bob)
            }
        }
    }

    private func earbuds(_ set: ProductImages.EarbudSet, bob: Double) -> some View {
        ZStack {
            product(set.chargingCase, height: 38)
                .offset(y: motion.caseShown ? 16 : 26)
                .opacity(motion.caseShown ? (event.isConnected ? 1 : 0.55) : 0)
            bud(set.left, side: -1, isOut: motion.leftOut, bob: bob)
            bud(set.right, side: 1, isOut: motion.rightOut, bob: -bob)
        }
    }

    /// An earbud tucked into the case (small, hidden, at the opening) or
    /// lifted out beside its pair with a slight outward tilt.
    private func bud(_ image: NSImage, side: CGFloat, isOut: Bool, bob: Double) -> some View {
        product(image, height: 34)
            .rotationEffect(.degrees(isOut ? Double(side) * 6 : 0))
            .scaleEffect(isOut ? 1 : 0.6)
            .offset(x: isOut ? side * 14 : side * 4, y: isOut ? -15 + bob : 12)
            .opacity(isOut ? 1 : 0)
    }

    @ViewBuilder private func single(bob: Double) -> some View {
        Group {
            if let image = ProductImages.overEar(for: event.model) {
                product(image, height: 60)
            } else {
                Image(systemName: event.model.symbolName)
                    .font(.system(size: 34, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(motion.leftOut ? 1 : 0.85)
        .offset(y: motion.leftOut ? bob : 8)
        .opacity(motion.leftOut ? (event.isConnected ? 1 : 0.45) : 0)
    }

    private func product(_ image: NSImage, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
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
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                motion.caseShown = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.22)) {
                motion.leftOut = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.32)) {
                motion.rightOut = true
            }
        } else {
            // Start out of the case, then put them away.
            motion.caseShown = true
            motion.leftOut = true
            motion.rightOut = true
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.32).delay(0.25)) {
                    motion.leftOut = false
                }
                withAnimation(.easeIn(duration: 0.32).delay(0.33)) {
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

/// Rings for left / right / case, or a single ring for over-ear. White like
/// the system Batteries widget; orange only when low.
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
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: Double(level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .font(.system(size: 8.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.primary)
            }
            .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.Text.tertiary)
                .fixedSize()
        }
    }
}

extension HeadphoneModel {
    /// SF Symbol stand-in when the product renders aren't available.
    var symbolName: String {
        let preferred: String
        switch self {
        case .airPods: preferred = "airpods.gen3"
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
