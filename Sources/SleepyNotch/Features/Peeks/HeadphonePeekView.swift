import SwiftUI

/// Headphones connecting or disconnecting, laid out like the Batteries
/// widget: the name on top, then one big ring per part with Apple's own
/// render of that part inside it (see `ProductImages`) and its percentage
/// underneath. AirPods show the left bud, the right bud and the case;
/// over-ear headphones show one ring.
///
/// The intro is choreographed on an `IntroClock` (see `HeadphonePeekScene`)
/// and runs for about two seconds, then the clock stops: nothing ticks once
/// it has settled. Battery levels usually arrive a moment after the
/// connection; the rings fill when they do, which runs the clock again
/// briefly.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var clock = IntroClock()

    /// When the rings start filling, if the levels are already known.
    private static let fillAt: Double = 0.6
    private static let fillLength: Double = 1.6

    /// AirPods connecting get the unboxing (see `AirPodsConnectScene`);
    /// everything else, and every disconnect, the plain row of rings.
    private var earbuds: ProductImages.Earbuds? {
        event.isConnected ? ProductImages.earbuds(for: event.model) : nil
    }

    var body: some View {
        if let earbuds {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.isRunning)) { timeline in
                AirPodsConnectScene(
                    event: event,
                    buds: earbuds,
                    t: clock.time(at: timeline.date),
                    travelStart: min(clock.mark("travel"), AirPodsConnectScene.travelCap),
                    levelsAt: clock.mark("fill")
                )
            }
            .onAppear {
                if reduceMotion {
                    clock.finish()
                } else {
                    clock.run(until: AirPodsConnectScene.endTime(travelStart: AirPodsConnectScene.travelCap, levelsAt: 0))
                }
                levelsArrived(event.battery)
            }
            .onChange(of: event.battery) { levelsArrived($0) }
        } else {
            rings
        }
    }

    /// Levels in: the unboxing moves on to the rings once every part has
    /// reported (or at the cap), and the rings fill once both have happened.
    private func levelsArrived(_ battery: HeadphoneBattery?) {
        guard let battery else { return }
        let travel = battery.isComplete(for: event.model)
            ? AirPodsConnectScene.earliestTravel
            : AirPodsConnectScene.travelCap
        if travel < clock.mark("travel") {
            clock.set("travel", at: travel, runningUntil: 0)
        }
        if !clock.mark("fill").isFinite {
            clock.set("fill", at: 0, runningUntil: 0)
        }
        let travelStart = min(clock.mark("travel"), AirPodsConnectScene.travelCap)
        clock.set("fill", at: clock.mark("fill"), runningUntil: AirPodsConnectScene.endTime(travelStart: travelStart, levelsAt: clock.mark("fill")))
        if reduceMotion { clock.finish() }
    }

    private var rings: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !clock.isRunning)) { timeline in
            HeadphonePeekScene(
                event: event,
                t: clock.time(at: timeline.date),
                fillStart: clock.mark("fill")
            )
        }
        .onAppear {
            if event.battery != nil {
                clock.begin("fill", earliest: Self.fillAt, duration: Self.fillLength)
            }
            if reduceMotion {
                clock.finish()
            } else {
                clock.run(until: event.battery == nil ? 1.4 : Self.fillAt + Self.fillLength)
            }
        }
        .onChange(of: event.battery) { battery in
            guard battery != nil, !clock.mark("fill").isFinite else { return }
            clock.begin("fill", earliest: Self.fillAt, duration: Self.fillLength)
            if reduceMotion { clock.finish() }
        }
    }
}

/// The headphone peek at one moment of its intro, `t` seconds in — a pure
/// function of time, so any frame can be drawn on its own.
///
/// Connecting: the name drops in; the parts pop into their discs one after
/// another, earbuds spinning a full turn as they rise into place, over-ear
/// headphones turning in to face you, the case hopping once. Then each ring
/// sweeps around from empty while its number counts up, and both give a
/// small kick as they land. Other headphones get a glyph that drops in with
/// a wobble and sends two waves of sound out of its ring.
///
/// Disconnecting: the parts arrive, then tip apart, sink and dim.
struct HeadphonePeekScene: View {
    let event: HeadphoneEvent
    let t: Double
    /// When the rings start filling; infinite until the levels arrive.
    let fillStart: Double

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
            .opacity(IntroCurve.easeOut(t, start: 0.05, duration: 0.3))
            .offset(y: (1 - IntroCurve.spring(t, start: 0.05, response: 0.45, damping: 0.8)) * -8)

            HStack(spacing: 26) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    GaugeScene(
                        part: part,
                        t: t,
                        appearAt: 0.15 + Double(index) * 0.1,
                        fillAt: fillStart + Double(index) * 0.12,
                        isConnected: event.isConnected
                    )
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Parts

    /// Buds this close in level share one ring.
    private static let pairTolerance = 5

    /// One ring per part. Before the levels arrive every part shows; once
    /// they do, a part macOS has no level for (often the case, while the
    /// earbuds are out of it) bows out.
    private var parts: [GaugePart] {
        let battery = event.isConnected ? event.battery : nil

        if let buds = ProductImages.earbuds(for: event.model) {
            if let battery, battery.left == nil, battery.right == nil, battery.caseLevel == nil, let main = battery.main {
                return [GaugePart(id: "main", art: .bud(buds.left, side: 0), level: main)]
            }
            var parts: [GaugePart]
            if let left = battery?.left, let right = battery?.right, abs(left - right) <= Self.pairTolerance {
                // Like iPhone: buds within a few percent share one ring.
                parts = [GaugePart(id: "pair", art: .pair(buds.left, buds.right), level: min(left, right))]
            } else {
                parts = [
                    GaugePart(id: "left", art: .bud(buds.left, side: -1), level: battery?.left),
                    GaugePart(id: "right", art: .bud(buds.right, side: 1), level: battery?.right),
                ]
            }
            if let chargingCase = buds.chargingCase {
                parts.append(GaugePart(id: "case", art: .chargingCase(chargingCase), level: battery?.caseLevel))
            }
            return battery == nil ? parts : parts.filter { $0.level != nil }
        }

        let art: GaugePart.Art = ProductImages.overEar(for: event.model)
            .map { .overEar($0) }
            ?? .symbol(event.model.symbolName)
        return [GaugePart(id: "main", art: art, level: battery?.main)]
    }
}

struct GaugePart: Identifiable {
    enum Art {
        /// An earbud; `side` is -1 left, 1 right, 0 for one standing alone.
        case bud(NSImage, side: Double)
        /// Both earbuds together, for one shared ring.
        case pair(NSImage, NSImage)
        case chargingCase(NSImage)
        case overEar(NSImage)
        /// A glyph for headphones without a render.
        case symbol(String)
    }

    let id: String
    let art: Art
    let level: Int?
}

/// One ring at time `t`: the part inside, the level around it, the number
/// below.
private struct GaugeScene: View {
    let part: GaugePart
    let t: Double
    let appearAt: Double
    let fillAt: Double
    let isConnected: Bool

    private static let size: CGFloat = 62
    private static let lineWidth: CGFloat = 4.5
    private static let fillDuration: Double = 0.95

    private var tint: Color {
        let level = part.level ?? 100
        if level <= 10 { return Theme.Status.critical }
        return level <= 20 ? Theme.Status.warning : Theme.Text.primary
    }

    /// 0 → 1 as the parts dim after a disconnect.
    private var dim: Double {
        isConnected ? 0 : IntroCurve.easeOut(t, start: appearAt + 0.45, duration: 0.55)
    }

    private var fill: Double {
        guard let level = part.level else { return 0 }
        return Double(level) / 100 * IntroCurve.easeOut(t, start: fillAt, duration: Self.fillDuration)
    }

    /// The kick both ring and number give as the fill lands.
    private var landing: Double {
        IntroCurve.bump(t, start: fillAt + Self.fillDuration - 0.15, duration: 0.32)
    }

    var body: some View {
        let pop = IntroCurve.spring(t, start: appearAt, response: 0.42, damping: 0.55)

        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))

                if part.level != nil {
                    Group {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: Self.lineWidth)
                        Circle()
                            .trim(from: 0, to: fill)
                            .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(Self.lineWidth / 2)
                    .opacity(IntroCurve.linear(t, start: fillAt - 0.15, duration: 0.2))
                } else if isConnected {
                    // Levels on their way: a faint arc circling the track,
                    // so the wait reads as deliberate rather than empty.
                    WaitingArc(lineWidth: Self.lineWidth)
                        .padding(Self.lineWidth / 2)
                        .opacity(IntroCurve.linear(t, start: appearAt + 0.3, duration: 0.3))
                        .transition(.opacity)
                }

                art
                    .opacity(1 - 0.55 * dim)
            }
            .frame(width: Self.size, height: Self.size)
            .scaleEffect((0.3 + 0.7 * pop) * (1 + 0.06 * landing) * (1 - 0.08 * dim))
            .opacity(IntroCurve.linear(t, start: appearAt, duration: 0.12))

            Group {
                if part.level != nil {
                    CountingPercent(value: fill * 100)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                        .scaleEffect(1 + 0.14 * landing)
                        .opacity(IntroCurve.linear(t, start: fillAt - 0.05, duration: 0.2))
                } else if isConnected {
                    // Keeps the row's height while the levels are on their way.
                    Text(" ").font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Art

    @ViewBuilder private var art: some View {
        switch part.art {
        case .bud(let image, let side):
            // A full turn as it rises into place, landing with a little
            // overshoot; disconnecting tips it outward and lets it sink.
            let a = IntroCurve.spring(t, start: appearAt + 0.04, response: 0.75, damping: 0.72)
            product(image, height: 42)
                .rotation3DEffect(.degrees((1 - a) * 360 * (side < 0 ? -1 : 1)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotationEffect(.degrees(side * 14 * dim))
                .scaleEffect(0.55 + 0.45 * a)
                .offset(y: (1 - a) * 22 + 4 * dim)
                .opacity(IntroCurve.linear(t, start: appearAt + 0.04, duration: 0.15))
        case .pair(let left, let right):
            // The two buds meet in the middle of the ring.
            let a = IntroCurve.spring(t, start: appearAt + 0.04, response: 0.6, damping: 0.7)
            HStack(spacing: 2) {
                productImage(left).frame(width: 18, height: 34)
                    .offset(x: (1 - a) * -10)
                productImage(right).frame(width: 18, height: 34)
                    .offset(x: (1 - a) * 10)
            }
            .scaleEffect(0.6 + 0.4 * a)
            .offset(y: (1 - a) * 14 + 4 * dim)
            .opacity(IntroCurve.linear(t, start: appearAt + 0.04, duration: 0.15))
        case .chargingCase(let image):
            // Pops in, then hops once.
            let a = IntroCurve.spring(t, start: appearAt + 0.04, response: 0.5, damping: 0.5)
            product(image, height: 32)
                .scaleEffect(0.5 + 0.5 * a)
                .offset(y: -6 * IntroCurve.bump(t, start: appearAt + 0.45, duration: 0.32) + 4 * dim)
                .opacity(IntroCurve.linear(t, start: appearAt + 0.04, duration: 0.15))
        case .overEar(let image):
            // Turns in from the side to face you.
            let a = IntroCurve.spring(t, start: appearAt + 0.04, response: 0.7, damping: 0.68)
            product(image, height: 44)
                .rotation3DEffect(.degrees((1 - a) * 80), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .scaleEffect(0.6 + 0.4 * a)
                .offset(y: (1 - a) * -10 + 4 * dim)
                .opacity(IntroCurve.linear(t, start: appearAt + 0.04, duration: 0.15))
        case .symbol(let name):
            symbolArt(name)
        }
    }

    /// Drops in with a wobble, then two waves of sound leave the ring.
    private func symbolArt(_ name: String) -> some View {
        let start = appearAt + 0.06
        let drop = IntroCurve.spring(t, start: start, response: 0.5, damping: 0.42)
        let since = max(0, t - start)
        let wobble = since > 0 && since < 5 ? sin(since * 16) * 12 * exp(-since * 5) : 0

        return ZStack {
            ForEach(0..<2, id: \.self) { wave in
                let p = IntroCurve.linear(t, start: start + 0.3 + Double(wave) * 0.3, duration: 0.7)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    SoundArc()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 9, height: 18)
                        .scaleEffect(x: side * (0.9 + 0.4 * p), y: 0.9 + 0.4 * p)
                        .offset(x: side * (34 + 18 * p))
                        .opacity(p > 0 && p < 1 ? (1 - p) * 0.85 : 0)
                }
            }
            Image(systemName: name)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(wobble))
                .scaleEffect(0.5 + 0.5 * drop)
                .offset(y: (1 - drop) * -20 + 4 * dim)
                .opacity(IntroCurve.linear(t, start: start, duration: 0.12))
        }
    }

    private func product(_ image: NSImage, height: CGFloat) -> some View {
        productImage(image)
            .frame(width: Self.size - 16, height: height)
    }

    private func productImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
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

/// A short arc circling a ring's track while its level is on the way. It
/// only exists until the level lands, so its frames stop with it.
struct WaitingArc: View {
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
        }
    }
}
