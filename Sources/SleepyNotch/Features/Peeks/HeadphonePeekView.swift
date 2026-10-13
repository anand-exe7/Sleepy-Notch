import SwiftUI

/// Headphones connecting or disconnecting, laid out like the Batteries
/// widget: the name on top, then one big ring per part with Apple's own
/// render of that part inside it (see `ProductImages`) and its percentage
/// underneath. AirPods show the left bud, the right bud and the case; over-ear
/// headphones show one ring.
///
/// Connecting, the parts pop into their rings one after another — earbuds
/// spin in to face you — then each ring fills from empty while its number
/// counts up. Battery levels usually arrive a moment after the connection;
/// the rings fill as soon as they do. Any pair without a render gets a
/// headphones glyph that drops in with two sound arcs rippling out once.
/// Disconnecting shows the parts dimmed, without rings. Everything is
/// one-shot and settles inside the peek; nothing loops.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(event.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
                    .fixedSize()
            }
            .frame(height: 18)
            .padding(.horizontal, 24)

            HStack(spacing: 30) {
                ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                    BatteryGauge(
                        art: gauge.art,
                        level: gauge.level,
                        order: index,
                        isConnected: event.isConnected
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Parts

    private struct Gauge: Identifiable {
        let id: String
        let art: GaugeArt
        let level: Int?
    }

    /// One ring per part. Before the levels arrive every part shows; once
    /// they do, a part macOS has no level for (often the case, while the
    /// earbuds are out of it) bows out.
    private var gauges: [Gauge] {
        let battery = event.isConnected ? event.battery : nil

        if let buds = ProductImages.earbuds(for: event.model) {
            if let battery, battery.left == nil, battery.right == nil, battery.caseLevel == nil, let main = battery.main {
                return [Gauge(id: "main", art: .product(buds.left, height: 38, spins: true), level: main)]
            }
            var parts = [
                Gauge(id: "left", art: .product(buds.left, height: 38, spins: true), level: battery?.left),
                Gauge(id: "right", art: .product(buds.right, height: 38, spins: true), level: battery?.right),
            ]
            if let chargingCase = buds.chargingCase {
                parts.append(Gauge(id: "case", art: .product(chargingCase, height: 28, spins: false), level: battery?.caseLevel))
            }
            return battery == nil ? parts : parts.filter { $0.level != nil }
        }

        let art: GaugeArt = ProductImages.overEar(for: event.model)
            .map { .product($0, height: 40, spins: false) }
            ?? .symbol(event.model.symbolName)
        return [Gauge(id: "main", art: art, level: battery?.main)]
    }
}

/// What sits inside a ring.
enum GaugeArt {
    /// A product render; earbuds `spin` in to face you.
    case product(NSImage, height: CGFloat, spins: Bool)
    /// A glyph for headphones without a render.
    case symbol(String)
}

/// One ring: the part inside, the level around it, the number below.
private struct BatteryGauge: View {
    let art: GaugeArt
    let level: Int?
    /// Position in the row, for the stagger.
    let order: Int
    let isConnected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = GaugeState()

    private static let size: CGFloat = 58
    private static let lineWidth: CGFloat = 4

    private var tint: Color {
        (level ?? 100) <= 20 ? Theme.Status.warning : Theme.Text.primary
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))

                if level != nil {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: Self.lineWidth)
                        .padding(Self.lineWidth / 2)
                    Circle()
                        .trim(from: 0, to: state.fill)
                        .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(Self.lineWidth / 2)
                }

                artView
                    .opacity(isConnected ? 1 : 0.45)
            }
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(state.shown ? 1 : 0.6)
            .opacity(state.shown ? 1 : 0)

            Group {
                if level != nil {
                    CountingPercent(value: state.fill * 100)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                } else if isConnected {
                    // Keeps the row's height while the levels are on their way.
                    Text(" ").font(.system(size: 17, weight: .semibold))
                }
            }
            .opacity(state.shown ? 1 : 0)
        }
        .onAppear(perform: appear)
        .onChange(of: level) { _ in fillToLevel(after: 0.1) }
    }

    @ViewBuilder private var artView: some View {
        switch art {
        case .product(let image, let height, let spins):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.size - 18, height: height)
                .rotation3DEffect(
                    .degrees(spins && !state.artIn ? 90 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .scaleEffect(state.artIn ? 1 : 0.5)
                .opacity(state.artIn ? 1 : 0)
        case .symbol(let name):
            ZStack {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    SoundArc()
                        .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 9, height: 18)
                        .scaleEffect(x: side, y: 1)
                        .offset(x: side * (state.ripple ? 46 : 36))
                        .opacity(state.ripple ? 0 : (state.artIn ? 0.9 : 0))
                }
                Image(systemName: name)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(state.artIn ? 1 : 0.5)
                    .offset(y: state.artIn ? 0 : -12)
                    .opacity(state.artIn ? 1 : 0)
            }
        }
    }

    // MARK: - Motion

    private func appear() {
        guard !reduceMotion else {
            state.shown = true
            state.artIn = true
            state.ripple = true
            state.fill = Double(level ?? 0) / 100
            return
        }
        let stagger = Double(order) * 0.09
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.1 + stagger)) {
            state.shown = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.66).delay(0.18 + stagger)) {
            state.artIn = true
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.5 + stagger)) {
            state.ripple = true
        }
        fillToLevel(after: 0.35 + stagger)
    }

    private func fillToLevel(after delay: Double) {
        let target = Double(level ?? 0) / 100
        guard !reduceMotion else {
            state.fill = target
            return
        }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.9).delay(delay)) {
            state.fill = target
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
private final class GaugeState: ObservableObject {
    @Published var shown = false
    @Published var artIn = false
    @Published var ripple = false
    @Published var fill: Double = 0
}
