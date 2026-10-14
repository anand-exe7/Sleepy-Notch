import SwiftUI

/// AirPods connecting, staged like the iPhone's pop-up — the case opening
/// and the buds coming out — in 2D, from Apple's own renders (see
/// `ProductImages`), at one moment `t` seconds in. A pure function of time,
/// like `HeadphonePeekScene`.
///
/// 1. **Arrive.** The case rises into the middle, larger than life.
/// 2. **Open.** It gives a quick squash and stretch, as if the lid flicked
///    up, and the buds rise out from behind it, each spinning a turn, then
///    hang there bobbing gently while the levels are read.
/// 3. **Settle.** Once every part has reported (or at `travelCap`), each
///    part glides down into its own ring — buds within a few percent share
///    one — and the rings fill while the numbers count up.
///
/// macOS ships no open-case render, so the lid itself isn't drawn.
struct AirPodsConnectScene: View {
    let event: HeadphoneEvent
    let buds: ProductImages.Earbuds
    let t: Double
    /// When the parts start gliding into their rings.
    let travelStart: Double
    /// When the levels arrived; infinite until they do.
    let levelsAt: Double

    /// The parts leave the hero no sooner than this, so the opening plays out
    /// even when the levels are already known.
    static let earliestTravel: Double = 1.25
    /// …and no later than this, levels or not.
    static let travelCap: Double = 2.4

    private static let travelResponse: Double = 0.62
    private static let fillDuration: Double = 0.95
    private static let ringSize: CGFloat = 62
    private static let ringGap: CGFloat = 26
    private static let lineWidth: CGFloat = 4.5

    /// How long the clock must run for everything to settle.
    static func endTime(travelStart: Double, levelsAt: Double) -> Double {
        max(travelStart + 0.45, levelsAt.isFinite ? levelsAt : 0) + 0.12 * 2 + fillDuration + 0.4
    }

    private var fillStart: Double {
        levelsAt.isFinite ? max(travelStart + 0.45, levelsAt) : .infinity
    }

    /// 0 in the hero, 1 in the rings.
    private var travel: Double {
        IntroCurve.spring(t, start: travelStart, response: Self.travelResponse, damping: 0.8)
    }

    // MARK: - Layout (in the peek's own coordinates, origin top left)

    private static let headerY: CGFloat = 15
    private static let ringY: CGFloat = 36 + ringSize / 2
    private static let heroCaseY: CGFloat = 92
    private static let heroBudY: CGFloat = 50

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                header
                    .frame(width: proxy.size.width)
                    .position(x: mid, y: Self.headerY)

                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    ring(slot, index: index)
                        .position(x: slotX(index, mid: mid), y: Self.ringY)
                    if slot.level != nil {
                        number(slot, index: index)
                            .position(x: slotX(index, mid: mid), y: Self.ringY + Self.ringSize / 2 + 17)
                    }
                }

                // Drawn behind the case, so the buds rise out of it.
                bud(buds.left, side: -1, mid: mid)
                bud(buds.right, side: 1, mid: mid)
                chargingCase(mid: mid)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(event.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("Connected")
                .font(.system(size: 13))
                .foregroundColor(Theme.Text.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .opacity(IntroCurve.easeOut(t, start: 0.05, duration: 0.3))
        .offset(y: (1 - IntroCurve.spring(t, start: 0.05, response: 0.45, damping: 0.8)) * -8)
    }

    // MARK: - Slots

    /// A ring and what settles into it.
    private struct Slot: Identifiable {
        enum Holds { case left, right, pair, chargingCase }
        let id: String
        let holds: Holds
        let level: Int?
    }

    /// Before the levels arrive there's a ring for every part; after, a part
    /// with no level (often the case, when the buds are out of it) bows out,
    /// and buds within a few percent share one ring, like on iPhone.
    private var slots: [Slot] {
        let battery = event.battery
        if let battery, battery.left == nil, battery.right == nil, let main = battery.main {
            return [Slot(id: "pair", holds: .pair, level: main)]
        }
        var slots: [Slot]
        if let left = battery?.left, let right = battery?.right, abs(left - right) <= 5 {
            slots = [Slot(id: "pair", holds: .pair, level: min(left, right))]
        } else {
            slots = [
                Slot(id: "left", holds: .left, level: battery?.left),
                Slot(id: "right", holds: .right, level: battery?.right),
            ]
        }
        if buds.chargingCase != nil {
            slots.append(Slot(id: "case", holds: .chargingCase, level: battery?.caseLevel))
        }
        return battery == nil ? slots : slots.filter { $0.level != nil }
    }

    private func slotX(_ index: Int, mid: CGFloat) -> CGFloat {
        let count = CGFloat(slots.count)
        return mid + (CGFloat(index) - (count - 1) / 2) * (Self.ringSize + Self.ringGap)
    }

    private func slotIndex(_ holds: Slot.Holds) -> Int? {
        slots.firstIndex { $0.holds == holds }
    }

    private func slot(at index: Int) -> Slot? {
        slots.indices.contains(index) ? slots[index] : nil
    }

    // MARK: - Rings

    private func ringAppear(_ index: Int) -> Double {
        IntroCurve.spring(t, start: travelStart + 0.12 + Double(index) * 0.06, response: 0.45, damping: 0.75)
    }

    private func fill(_ slot: Slot, index: Int) -> Double {
        guard let level = slot.level else { return 0 }
        let start = fillStart + Double(index) * 0.12
        return Double(level) / 100 * IntroCurve.easeOut(t, start: start, duration: Self.fillDuration)
    }

    private func landing(_ index: Int) -> Double {
        IntroCurve.bump(t, start: fillStart + Double(index) * 0.12 + Self.fillDuration - 0.15, duration: 0.32)
    }

    private func tint(_ slot: Slot) -> Color {
        let level = slot.level ?? 100
        if level <= 10 { return Theme.Status.critical }
        return level <= 20 ? Theme.Status.warning : Theme.Text.primary
    }

    private func ring(_ slot: Slot, index: Int) -> some View {
        let appear = ringAppear(index)
        return ZStack {
            Circle().fill(Color.white.opacity(0.07))
            if slot.level != nil {
                Group {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: Self.lineWidth)
                    Circle()
                        .trim(from: 0, to: fill(slot, index: index))
                        .stroke(tint(slot), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(Self.lineWidth / 2)
            } else {
                WaitingArc(lineWidth: Self.lineWidth)
                    .padding(Self.lineWidth / 2)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .scaleEffect((0.82 + 0.18 * appear) * (1 + 0.06 * landing(index)))
        .opacity(IntroCurve.linear(t, start: travelStart + 0.12 + Double(index) * 0.06, duration: 0.2))
    }

    private func number(_ slot: Slot, index: Int) -> some View {
        CountingPercent(value: fill(slot, index: index) * 100)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(tint(slot))
            .scaleEffect(1 + 0.14 * landing(index))
            .opacity(IntroCurve.linear(t, start: fillStart + Double(index) * 0.12 - 0.05, duration: 0.2))
    }

    // MARK: - The case

    private func chargingCase(mid: CGFloat) -> some View {
        let rise = IntroCurve.spring(t, start: 0.05, response: 0.5, damping: 0.7)
        // The lid flicking open: a squash, then a stretch.
        let squash = IntroCurve.bump(t, start: 0.5, duration: 0.16)
        let stretch = IntroCurve.bump(t, start: 0.64, duration: 0.24)
        let target = slotIndex(.chargingCase)
        let p = travel
        let toX = target.map { slotX($0, mid: mid) } ?? mid
        let height = lerp(50, 32, p)

        return Group {
            if let image = buds.chargingCase {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: height)
                    .scaleEffect(
                        x: 1 + 0.07 * squash - 0.03 * stretch,
                        y: 1 - 0.09 * squash + 0.06 * stretch,
                        anchor: .bottom
                    )
                    .scaleEffect(0.55 + 0.45 * rise)
                    // A case with no ring of its own sinks away.
                    .scaleEffect(target == nil ? 1 - 0.4 * p : 1)
                    .opacity(IntroCurve.linear(t, start: 0.05, duration: 0.15) * (target == nil ? 1 - p : 1))
                    .position(
                        x: lerp(mid, toX, p),
                        y: lerp(Self.heroCaseY + (1 - rise) * 26, Self.ringY + (target == nil ? 14 : 0), p)
                    )
            }
        }
    }

    // MARK: - The buds

    private func bud(_ image: NSImage, side: Double, mid: CGFloat) -> some View {
        let start = 0.62 + (side < 0 ? 0 : 0.07)
        let rise = IntroCurve.spring(t, start: start, response: 0.7, damping: 0.68)
        let spin = IntroCurve.spring(t, start: start, response: 0.85, damping: 0.75)
        let p = travel

        // Hanging above the case, bobbing out of step with each other.
        let since = max(0, t - start - 0.5)
        let bob = sin(since * 3.4 + (side < 0 ? 0 : 1.3)) * 2.2 * min(since * 2, 1)

        let heroX = mid + CGFloat(side) * 21 * CGFloat(rise)
        let heroY = lerp(Self.heroCaseY - 4, Self.heroBudY, rise) + CGFloat(bob)
        let heroTilt = side * 14

        // Where it settles: its own ring, or beside its twin in a shared one.
        let target: (x: CGFloat, height: CGFloat)
        if let index = slotIndex(side < 0 ? .left : .right) {
            target = (slotX(index, mid: mid), 42)
        } else if let index = slotIndex(.pair) {
            target = (slotX(index, mid: mid) + CGFloat(side) * 10, 34)
        } else {
            target = (mid, 34)
        }

        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 44, height: lerp(44, target.height, p))
            .rotation3DEffect(.degrees((1 - spin) * 360 * (side < 0 ? -1 : 1)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotationEffect(.degrees(heroTilt * (1 - p)))
            .scaleEffect(0.5 + 0.5 * rise)
            .opacity(IntroCurve.linear(t, start: start, duration: 0.12))
            .position(x: lerp(heroX, target.x, p), y: lerp(heroY, Self.ringY + 3, p))
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat {
        a + (b - a) * CGFloat(p)
    }
}
