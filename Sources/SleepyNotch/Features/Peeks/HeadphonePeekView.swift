import SwiftUI

/// Headphones connecting or disconnecting, shown big and centred with
/// Apple's real product renders (see `ProductImages`), battery levels above.
///
/// Connecting AirPods plays the moment you know from the iPhone: the case
/// pops up, its lid swings open, and the left then right earbud spin up out
/// of it and settle above. Disconnecting reverses it — earbuds spin back in,
/// the lid closes, the case dims. Over-ear models pop in as one piece.
/// Everything settles and holds still; nothing loops.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = HeadphoneMotion()

    var body: some View {
        VStack(spacing: 4) {
            batteryRow
                .frame(height: 20)

            stage
                .frame(width: 220, height: 92)

            HStack(spacing: 6) {
                Text(event.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
            }
            .lineLimit(1)
            .frame(height: 18)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: animate)
    }

    // MARK: - Battery

    @ViewBuilder private var batteryRow: some View {
        if event.isConnected, let battery = event.battery {
            HStack(spacing: 18) {
                if let main = battery.main {
                    BatteryChip(label: "Battery", level: main)
                } else {
                    if let left = battery.left { BatteryChip(label: "L", level: left) }
                    if let right = battery.right { BatteryChip(label: "R", level: right) }
                    if let caseLevel = battery.caseLevel { BatteryChip(label: "Case", level: caseLevel) }
                }
            }
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        Group {
            if let set = ProductImages.earbuds(for: event.model) {
                earbuds(set)
            } else {
                single
            }
        }
        .scaleEffect(motion.shown ? 1 : 0.72)
        .opacity(motion.shown ? (event.isConnected ? 1 : 0.5) : 0)
    }

    private static let caseHeight: CGFloat = 56
    private static let budHeight: CGFloat = 46

    /// Case at the bottom of the stage; earbuds rise out of it to sit above.
    /// Drawn back to front — lid, earbuds, case body — so the body hides the
    /// earbuds while they're inside, and the open lid sits behind them.
    private func earbuds(_ set: ProductImages.EarbudSet) -> some View {
        let caseY: CGFloat = 92 / 2 - Self.caseHeight / 2
        return ZStack {
            caseImage(set, part: .lid)
                // Hinged at the lid line, the lid tips back away from you and
                // stays attached to the case, like opening the real thing.
                .rotation3DEffect(
                    .degrees(motion.lidOpen ? -72 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: UnitPoint(x: 0.5, y: set.lidFraction),
                    perspective: 0.5
                )
                .offset(y: caseY)
            bud(set.left, side: -1, isOut: motion.leftOut)
            bud(set.right, side: 1, isOut: motion.rightOut)
            caseImage(set, part: .body)
                .offset(y: caseY)
        }
    }

    private enum CasePart { case lid, body }

    /// The case render cut at the lid line, so the lid can move on its own.
    /// The body reaches 1pt up under the lid so the two halves overlap
    /// instead of leaving an anti-aliased hairline between them.
    private func caseImage(_ set: ProductImages.EarbudSet, part: CasePart) -> some View {
        let lidHeight = Self.caseHeight * set.lidFraction
        let cut = part == .lid ? lidHeight : lidHeight - 1
        return product(set.chargingCase, height: Self.caseHeight)
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(part == .lid ? Color.black : Color.clear)
                        .frame(height: cut)
                    Rectangle()
                        .fill(part == .body ? Color.black : Color.clear)
                }
            )
    }

    /// Inside the case (low, small, turned away) or out above it, upright,
    /// spun once on the way.
    private func bud(_ image: NSImage, side: CGFloat, isOut: Bool) -> some View {
        product(image, height: Self.budHeight)
            .rotation3DEffect(.degrees(isOut ? 0 : Double(side) * -360), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(isOut ? 1 : 0.7)
            .offset(x: side * (isOut ? 25 : 8), y: isOut ? -22 : 22)
            .opacity(isOut ? 1 : 0)
    }

    @ViewBuilder private var single: some View {
        Group {
            if let image = ProductImages.overEar(for: event.model) {
                product(image, height: 84)
            } else {
                Image(systemName: event.model.symbolName)
                    .font(.system(size: 54, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white)
            }
        }
        .rotation3DEffect(.degrees(motion.leftOut ? 0 : 30), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
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
                motion.shown = true
                motion.lidOpen = true
                motion.leftOut = true
                motion.rightOut = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                motion.shown = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.3)) {
                motion.lidOpen = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.76).delay(0.55)) {
                motion.leftOut = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.76).delay(0.68)) {
                motion.rightOut = true
            }
        } else {
            // Start open with the earbuds out, then put everything away.
            motion.shown = true
            motion.lidOpen = true
            motion.leftOut = true
            motion.rightOut = true
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.45).delay(0.2)) {
                    motion.leftOut = false
                }
                withAnimation(.easeIn(duration: 0.45).delay(0.28)) {
                    motion.rightOut = false
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.75)) {
                    motion.lidOpen = false
                }
            }
        }
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class HeadphoneMotion: ObservableObject {
    @Published var shown = false
    @Published var lidOpen = false
    @Published var leftOut = false
    @Published var rightOut = false
}

/// "L ▭ 92%": a label, a small battery, and the level. Orange when low.
private struct BatteryChip: View {
    let label: String
    let level: Int

    private var tint: Color {
        level <= 20 ? Theme.Status.warning : Theme.Text.primary
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.Text.tertiary)
            MiniBattery(level: level, tint: tint)
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(tint)
        }
        .fixedSize()
    }
}

private struct MiniBattery: View {
    let level: Int
    let tint: Color

    private static let bodyWidth: CGFloat = 22
    private static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(
                        width: max(2, (Self.bodyWidth - Self.inset * 2) * CGFloat(level) / 100),
                        height: 7
                    )
                    .offset(x: Self.inset)
            }
            .frame(width: Self.bodyWidth, height: 11)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
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
