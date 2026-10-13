import SwiftUI

/// Headphones connecting or disconnecting: the product, its name, and its
/// battery, in one row under the notch — the same layout as the charging
/// peek.
///
/// The product is Apple's own render where macOS has one (see
/// `ProductImages`): AirPods are the two earbuds, which spin up into place
/// one after the other; AirPods Max and Beats turn in to face you. Any other
/// pair gets a headphones glyph that drops in with two sound arcs rippling
/// out once. Disconnecting shows the product settling back and dimming.
/// Everything is one-shot and settles well inside the peek; nothing loops.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = HeadphoneMotion()

    var body: some View {
        HStack(spacing: 14) {
            art
                .scaleEffect(dimmed ? 0.9 : 1)
                .offset(y: dimmed ? 3 : 0)
                .frame(width: 58, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
            }

            Spacer(minLength: 8)

            if event.isConnected, let battery = event.battery {
                HeadphoneBatteryView(battery: battery)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
            }
        }
        .padding(.horizontal, 20)
        .onAppear(perform: animate)
    }

    // MARK: - Art

    @ViewBuilder private var art: some View {
        if let buds = ProductImages.earbuds(for: event.model) {
            earbuds(buds)
        } else if let image = ProductImages.overEar(for: event.model) {
            overEar(image)
        } else {
            genericHeadphones
        }
    }

    /// The pair side by side, angled slightly apart like Apple's own battery
    /// widget. Each one spins up from below into place.
    private func earbuds(_ buds: ProductImages.Earbuds) -> some View {
        ZStack {
            bud(buds.left, side: -1, isIn: motion.left)
            bud(buds.right, side: 1, isIn: motion.right)
        }
        .opacity(dimmed ? 0.45 : 1)
    }

    private func bud(_ image: NSImage, side: CGFloat, isIn: Bool) -> some View {
        product(image, height: 44)
            .rotation3DEffect(.degrees(isIn ? 0 : Double(side) * 75), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotationEffect(.degrees(Double(side) * (isIn ? 7 : 18)))
            .scaleEffect(isIn ? 1 : 0.6)
            .offset(x: side * (isIn ? 12 : 4), y: isIn ? 0 : 16)
            .opacity(isIn ? 1 : 0)
    }

    /// Over-ear: turns in from the side to face you.
    private func overEar(_ image: NSImage) -> some View {
        product(image, height: 46)
            .rotation3DEffect(.degrees(motion.left ? 0 : 50), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(motion.left ? 1 : 0.7)
            .offset(y: motion.left ? 0 : -6)
            .opacity(motion.left ? (dimmed ? 0.45 : 1) : 0)
    }

    /// Any other headphones: a glyph on a soft disc. The disc pops, the
    /// glyph drops onto it, and two sound arcs ripple out once.
    private var genericHeadphones: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                SoundArc()
                    .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 10, height: 20)
                    .scaleEffect(x: side, y: 1)
                    .offset(x: side * (motion.ripple ? 33 : 24))
                    .opacity(motion.ripple ? 0 : (motion.right ? 0.9 : 0))
            }

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 44, height: 44)
                .scaleEffect(motion.left ? 1 : 0.5)
                .opacity(motion.left ? 1 : 0)

            Image(systemName: event.model.symbolName)
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(.white)
                .scaleEffect(motion.right ? 1 : 0.5)
                .offset(y: motion.right ? 0 : -12)
                .opacity(motion.right ? 1 : 0)
        }
        .opacity(dimmed ? 0.45 : 1)
    }

    private func product(_ image: NSImage, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }

    // MARK: - Motion

    private var dimmed: Bool { !event.isConnected && motion.dimmed }

    private func animate() {
        guard !reduceMotion else {
            motion.left = true
            motion.right = true
            motion.ripple = true
            motion.dimmed = true
            return
        }
        if event.isConnected {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68).delay(0.12)) {
                motion.left = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68).delay(0.24)) {
                motion.right = true
            }
            withAnimation(.easeOut(duration: 0.75).delay(0.5)) {
                motion.ripple = true
            }
        } else {
            // Arrives in place, then sinks back a little and dims.
            motion.left = true
            motion.right = true
            motion.ripple = true
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) {
                    motion.dimmed = true
                }
            }
        }
    }
}

/// A right-facing arc, like one wave of the speaker glyph.
private struct SoundArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 1.4, y: rect.midY)
        )
        return path
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class HeadphoneMotion: ObservableObject {
    @Published var left = false
    @Published var right = false
    @Published var ripple = false
    @Published var dimmed = false
}
