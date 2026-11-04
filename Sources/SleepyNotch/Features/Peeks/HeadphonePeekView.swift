import SwiftUI
import AppKit

/// Headphones connecting or disconnecting, after the iPhone's AirPods card.
///
/// Connecting, it plays in two beats, like iOS:
/// 1. **The product, big.** It rises from the bottom of the card, larger
///    than life, with nothing else on screen, and does its thing there:
///    AirPods open their lid (Apple's own 3D clip, see `ProductVideo`;
///    without it, the case gives a flick), other earbuds' case opens into the
///    buds, headphones turn in or bounce.
/// 2. **Settling.** It shrinks down into its place in the middle; then the
///    name and a green check arrive under the notch, AirPods' buds fly out
///    of the case to either side, and the batteries fill.
///
/// Disconnecting skips the first beat: the product is in place, the buds go
/// home and it dims.
///
/// Every step is a one-shot spring started by a one-shot timer, so nothing
/// runs once the card has settled.
struct HeadphonePeekView: View {
    let event: HeadphoneEvent

    @StateObject private var reveal = HeadphoneReveal()

    /// The height the peek drops below the notch.
    static let contentHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            titleRow
                .padding(.top, 16)

            Spacer(minLength: 0)

            HeadphoneParts(event: event, reveal: reveal, levels: levels)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reveal.run(
                isConnected: event.isConnected,
                hasLevels: levels.hasAny,
                entrance: HeadphoneParts.entrance(for: event.model)
            )
        }
        .onChange(of: levels.hasAny) { has in
            if has { reveal.levelsArrived() }
        }
        .onDisappear { reveal.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Title

    /// "AirPods Pro  ✓ Connected", centred under the notch.
    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(event.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .modifier(RiseIn(shown: reveal.title))

            HStack(spacing: 4) {
                Image(systemName: event.isConnected ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(event.isConnected ? Theme.Status.charging : Theme.Text.tertiary)
                    .scaleEffect(reveal.status ? 1 : 0.3)
                Text(event.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                    .fixedSize()
            }
            .opacity(reveal.status ? 1 : 0)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Levels

    private var levels: PartLevels {
        guard event.isConnected, let battery = event.battery else { return PartLevels() }
        switch event.model {
        case .airPods, .airPodsPro, .earbuds:
            if battery.left == nil, battery.right == nil, battery.caseLevel == nil, let main = battery.main {
                return PartLevels(left: main, right: main)
            }
            return PartLevels(left: battery.left, right: battery.right, chargingCase: battery.caseLevel)
        case .airPodsMax, .beats, .headphones:
            return PartLevels(main: battery.main ?? battery.left ?? battery.right)
        }
    }

    private var accessibilityText: String {
        var text = "\(event.name), \(event.isConnected ? "connected" : "disconnected")"
        let parts: [(String, Int?)] = [
            ("left", levels.left), ("right", levels.right),
            ("case", levels.chargingCase), ("battery", levels.main),
        ]
        for (name, level) in parts {
            if let level { text += ", \(name) \(level) percent" }
        }
        return text
    }
}

/// Each part's battery level, where macOS knows it.
struct PartLevels: Equatable {
    var left: Int?
    var right: Int?
    var chargingCase: Int?
    var main: Int?

    var hasAny: Bool { left != nil || right != nil || chargingCase != nil || main != nil }
}

/// How a product makes its entrance, which sets when it settles.
enum HeadphoneEntrance {
    /// Apple's AirPods Pro clip: the lid opens while the case is big.
    case caseClip
    /// Regular AirPods: Apple's clip of their case turning a full circle.
    case caseSpin
    /// Regular AirPods without that clip: their case's lid swings open and
    /// the buds rise.
    case caseLid
    /// Anything else: a shorter moment big.
    case still
}

// MARK: - Parts

/// The product and its batteries.
private struct HeadphoneParts: View {
    let event: HeadphoneEvent
    @ObservedObject var reveal: HeadphoneReveal
    let levels: PartLevels

    static func entrance(for model: HeadphoneModel) -> HeadphoneEntrance {
        if ProductImages.caseOpeningVideo(for: model) != nil { return .caseClip }
        if ProductImages.caseSpinVideo(for: model) != nil { return .caseSpin }
        if model == .airPods, ProductImages.earbuds(for: .airPods)?.chargingCase != nil { return .caseLid }
        return .still
    }

    var body: some View {
        Group {
            if let video = ProductImages.caseOpeningVideo(for: event.model) {
                VStack(spacing: 6) {
                    caseClip(video)
                    groupedBatteries(budSymbol: event.model.symbolName,
                                     leftSymbol: budSymbol(left: true),
                                     rightSymbol: budSymbol(left: false),
                                     caseSymbol: caseSymbol)
                        .frame(height: BatteryBar.height)
                }
            } else if let spin = ProductImages.caseSpinVideo(for: event.model) {
                VStack(spacing: 6) {
                    caseSpin(spin)
                    groupedBatteries(budSymbol: event.model.symbolName,
                                     leftSymbol: budSymbol(left: true),
                                     rightSymbol: budSymbol(left: false),
                                     caseSymbol: caseSymbol)
                        .frame(height: BatteryBar.height)
                }
            } else if event.model == .airPods,
                      let buds = ProductImages.earbuds(for: .airPods),
                      let chargingCase = buds.chargingCase {
                VStack(spacing: 8) {
                    RegularAirPodsCase(
                        parts: buds,
                        chargingCase: chargingCase,
                        lidOpen: reveal.flick,
                        budsUp: reveal.budsOut,
                        width: 72
                    )
                    .frame(height: Self.artHeight, alignment: .bottom)
                    .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.75, lift: 12))
                    groupedBatteries(budSymbol: event.model.symbolName,
                                     leftSymbol: budSymbol(left: true),
                                     rightSymbol: budSymbol(left: false),
                                     caseSymbol: caseSymbol)
                        .frame(height: BatteryBar.height)
                }
            } else if let buds = ProductImages.earbuds(for: event.model) {
                VStack(spacing: 9) {
                    airPods(buds)
                        .frame(height: Self.artHeight)
                    partBatteries
                        .frame(height: BatteryBar.height)
                }
            } else if event.model == .earbuds {
                VStack(spacing: 9) {
                    otherEarbuds
                        .frame(height: Self.artHeight)
                    groupedBatteries(budSymbol: "earbuds", leftSymbol: "earbuds", rightSymbol: "earbuds",
                                     caseSymbol: "earbuds.case.fill", sideLabels: true)
                        .frame(height: BatteryBar.height)
                }
            } else {
                VStack(spacing: 9) {
                    overEar
                        .frame(height: Self.artHeight)
                    singleBattery
                        .frame(height: BatteryBar.height)
                }
            }
        }
        // Dimmed as one picture when disconnecting, so nothing turns
        // see-through.
        .compositingGroup()
        .opacity(reveal.dimmed ? 0.5 : 1)
    }

    // MARK: Sizes

    private static let artHeight: CGFloat = 62
    private static let budSize = CGSize(width: 40, height: 58)
    private static let caseSize = CGSize(width: 70, height: 54)
    private static let gap: CGFloat = 26
    /// How far each bud's centre sits from the middle. The batteries use the
    /// same offsets, so each sits exactly under its part.
    private static var budX: CGFloat { caseSize.width / 2 + gap + budSize.width / 2 }
    private static var rowWidth: CGFloat { 2 * budX + budSize.width + 40 }

    // MARK: AirPods Pro: Apple's clip

    /// The part of Apple's clip that's used: the closed case, the lid
    /// swinging open, ending on the open case with the buds inside.
    private static let clipStart: Double = 0.3
    private static let clipEnd: Double = 1.85
    private static let videoSize = CGSize(width: 186, height: 98)
    /// The clip's transparent margin under the case is allowed to overlap
    /// the spacing, so the case can be bigger. (The margin above is where
    /// the lid swings up.)
    private static let videoBottomMargin: CGFloat = 12

    private func caseClip(_ video: URL) -> some View {
        ProductVideo(
            url: video,
            start: Self.clipStart,
            end: event.isConnected ? Self.clipEnd : nil,
            delay: HeadphoneReveal.clipStartsAt
        )
        .frame(width: Self.videoSize.width, height: Self.videoSize.height)
        // Big enough to fill the card, small enough that the open lid stays
        // inside it.
        .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.45, lift: 4))
        .padding(.bottom, -Self.videoBottomMargin)
    }

    // MARK: AirPods: Apple's clip of the case turning

    private static let spinSize: CGFloat = 96
    /// The clip's square frame has transparent room around the case.
    private static let spinMargin: CGFloat = 10

    /// The case comes in from in front of you and turns one full circle,
    /// twice as fast as Apple's loop, shrinking into place as it goes, so it
    /// lands facing you. Disconnecting, it just faces you.
    private func caseSpin(_ video: URL) -> some View {
        ProductVideo(
            url: video,
            start: 0,
            end: event.isConnected ? 5.95 : nil,
            delay: HeadphoneReveal.spinStartsAt,
            rate: 2
        )
        .frame(width: Self.spinSize, height: Self.spinSize)
        .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.7, lift: 4, fromFront: true))
        .padding(.vertical, -Self.spinMargin)
    }

    // MARK: AirPods: the case, then the buds fly out

    private func airPods(_ buds: ProductImages.Earbuds) -> some View {
        ZStack(alignment: .bottom) {
            // Behind the case, so they fly out from behind it.
            bud(buds.left, side: -1)
            bud(buds.right, side: 1)
            if let chargingCase = buds.chargingCase {
                product(chargingCase)
                    .frame(width: Self.caseSize.width, height: Self.caseSize.height)
                    // The lid flicking open: a quick squash and back.
                    .scaleEffect(x: reveal.squash ? 1.05 : 1, y: reveal.squash ? 0.92 : 1, anchor: .bottom)
                    .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.6, lift: 14))
            }
        }
        .frame(width: Self.rowWidth, height: Self.artHeight, alignment: .bottom)
    }

    /// A bud: out beside the case, facing you; or tucked in the middle,
    /// behind the case, turned edge-on.
    private func bud(_ image: NSImage, side: CGFloat) -> some View {
        let out = reveal.budsOut
        return product(image)
            .frame(width: Self.budSize.width, height: Self.budSize.height)
            .rotation3DEffect(.degrees(out ? 0 : Double(side) * 75), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(out ? 1 : 0.7, anchor: .bottom)
            .offset(x: out ? side * Self.budX : 0, y: out ? 0 : -6)
            // Only there once they're on their way out (the case is solid
            // by then).
            .opacity(out ? 1 : 0)
    }

    // MARK: Other earbuds: the case opens into the buds

    private var otherEarbuds: some View {
        Image(systemName: reveal.flick ? "earbuds" : "earbuds.case.fill")
            .font(.system(size: 40, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.white)
            .modifier(SymbolReplace())
            .frame(height: Self.artHeight)
            .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.95, lift: 14))
    }

    // MARK: Headphones

    @ViewBuilder private var overEar: some View {
        if let image = ProductImages.overEar(for: event.model) {
            // AirPods Max and Beats: Apple's render, turning in to face you.
            product(image)
                .frame(width: 76, height: Self.artHeight)
                .rotation3DEffect(.degrees(reveal.stage == .hidden ? 80 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.6, lift: 14))
        } else {
            // Other headphones: the symbol bounces once while it's big.
            Image(systemName: "headphones")
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white)
                .modifier(SymbolBounce(trigger: reveal.flick))
                .frame(height: Self.artHeight)
                .modifier(BigToSmall(stage: reveal.stage, bigScale: 1.75, lift: 14))
        }
    }

    private func product(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
    }

    // MARK: Batteries

    /// AirPods: each bud's and the case's battery right under it.
    private var partBatteries: some View {
        ZStack {
            bar(levels.left).offset(x: -Self.budX)
            bar(levels.chargingCase)
            bar(levels.right).offset(x: Self.budX)
        }
        .frame(width: Self.rowWidth)
    }

    /// One row under the product: the buds (together when within a few
    /// percent) and the case, like the iPhone's card.
    @ViewBuilder private func groupedBatteries(
        budSymbol: String, leftSymbol: String, rightSymbol: String, caseSymbol: String, sideLabels: Bool = false
    ) -> some View {
        if levels.hasAny {
            HStack(spacing: 22) {
                if let left = levels.left, let right = levels.right, abs(left - right) > 5 {
                    labelled(leftSymbol, left, side: sideLabels ? "L" : nil)
                    labelled(rightSymbol, right, side: sideLabels ? "R" : nil)
                } else if let buds = [levels.left, levels.right].compactMap({ $0 }).min() {
                    labelled(budSymbol, buds)
                }
                if let caseLevel = levels.chargingCase {
                    labelled(caseSymbol, caseLevel)
                }
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private var singleBattery: some View {
        if let main = levels.main {
            BatteryBar(level: main, shown: reveal.batteries)
        } else {
            placeholder
        }
    }

    private func labelled(_ symbol: String, _ level: Int, side: String? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white)
                .frame(minWidth: 16)
            if let side {
                Text(side)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.Text.secondary)
            }
            BatteryBar(level: level, shown: reveal.batteries)
        }
        .opacity(reveal.batteries ? 1 : 0)
    }

    /// A part's battery, or a placeholder holding its place, so nothing
    /// moves when the levels arrive a moment late.
    @ViewBuilder private func bar(_ level: Int?) -> some View {
        if let level {
            BatteryBar(level: level, shown: reveal.batteries)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.clear.frame(width: 1, height: BatteryBar.height)
    }

    /// The glyphs for each part in the battery row.
    private func budSymbol(left: Bool) -> String {
        let side = left ? "left" : "right"
        let name = event.model == .airPodsPro ? "airpodpro.\(side)" : "airpod.gen3.\(side)"
        return Self.symbol(name, or: Self.symbol("airpod.\(side)", or: event.model.symbolName))
    }

    private var caseSymbol: String {
        let name = event.model == .airPodsPro
            ? "airpodspro.chargingcase.wireless.fill"
            : "airpods.gen3.chargingcase.wireless.fill"
        return Self.symbol(name, or: Self.symbol("airpods.chargingcase.fill", or: "case.fill"))
    }

    private static func symbol(_ name: String, or fallback: String) -> String {
        SymbolAvailability.exists(name) ? name : fallback
    }
}

// MARK: - Battery

/// A battery like the iPhone's AirPods card: an outlined battery with its
/// terminal, filled to the level, and the percentage beside it. Centred as
/// a whole under its part.
private struct BatteryBar: View {
    let level: Int
    let shown: Bool

    static let height: CGFloat = 16
    private static let body = CGSize(width: 25, height: 12)

    private var tint: Color {
        if level <= 10 { return Theme.Status.critical }
        if level <= 20 { return Theme.Status.warning }
        return Theme.Status.charging
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: shown ? max(2, (Self.body.width - 4) * CGFloat(level) / 100) : 0)
                        .padding(2)
                }
                .frame(width: Self.body.width, height: Self.body.height)
                // The terminal.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 1.5, height: 4)
            }

            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.Text.primary)
                .fixedSize()
        }
        .fixedSize()
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 3)
    }
}

// MARK: - Motion

/// The product's two beats: below the card, then risen big into the middle
/// of the card, then down to its own size and place.
private struct BigToSmall: ViewModifier {
    let stage: HeadphoneReveal.Stage
    /// How much larger it is while big.
    let bigScale: CGFloat
    /// How far up it sits while big, to be in the middle of the card.
    let lift: CGFloat
    /// Comes from in front of you, like a camera pulling back: hidden, it's
    /// huge and low, only its top half in the card; it recedes into the
    /// middle. Otherwise it rises from below the card's edge.
    var fromFront = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(stage == .settled ? 1 : stage == .big || !fromFront ? bigScale : bigScale * 1.9)
            .offset(y: stage == .hidden ? (fromFront ? 46 : 150) : stage == .big ? -lift : 0)
            .opacity(stage == .hidden && fromFront ? 0 : 1)
    }
}

/// Text coming into place: a few points below and clear, then up and solid.
private struct RiseIn: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
    }
}

/// The system's own morph when a symbol changes (macOS 14 and later).
private struct SymbolReplace: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

/// One bounce of a symbol when `trigger` turns on (macOS 14 and later).
private struct SymbolBounce: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: trigger)
        } else {
            content
        }
    }
}

/// Which beats of the card have played. Each step is one spring, started
/// by a one-shot timer. A small object rather than `@State`, which this
/// toolchain can't build (see `NotchInteractionState`).
@MainActor
final class HeadphoneReveal: ObservableObject {
    enum Stage { case hidden, big, settled }

    @Published var stage: Stage = .hidden
    /// The product's moment while big: other earbuds' case opening into
    /// the buds, headphones' bounce. Stays on.
    @Published var flick = false
    /// AirPods' lid flicking open: a squash that springs back.
    @Published var squash = false
    @Published var budsOut = false
    @Published var title = false
    @Published var status = false
    @Published var batteries = false
    @Published var dimmed = false

    /// When Apple's clip starts playing: once the case has risen in.
    static let clipStartsAt: TimeInterval = 0.5
    /// When the AirPods case starts turning: as it comes in.
    static let spinStartsAt: TimeInterval = 0.25

    private var steps: [DispatchWorkItem] = []
    private var appeared = Date()
    /// The batteries fill no sooner than this, once everything has settled.
    private var earliestBatteries: TimeInterval = 1.7
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func run(isConnected: Bool, hasLevels: Bool, entrance: HeadphoneEntrance) {
        cancel()
        appeared = Date()
        if reduceMotion || !isConnected {
            // Straight to the settled product, no big beat.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                stage = .settled
                budsOut = true
                flick = true
            }
        }
        if reduceMotion {
            title = true; status = true; batteries = hasLevels
            budsOut = isConnected; dimmed = !isConnected
            return
        }

        guard isConnected else {
            // In place, then the buds go home and it dims.
            step(at: 0.1, .spring(response: 0.42, dampingFraction: 0.86)) { $0.title = true }
            step(at: 0.2, .spring(response: 0.4, dampingFraction: 0.7)) { $0.status = true }
            step(at: 0.5, .spring(response: 0.55, dampingFraction: 0.82)) { $0.budsOut = false }
            // The lid shuts (or the earbuds go back in their case).
            step(at: 0.68, .spring(response: 0.45, dampingFraction: 0.8)) { $0.flick = false }
            step(at: 0.75, .easeOut(duration: 0.5)) { $0.dimmed = true }
            return
        }

        // 1. Big: rising from below the card, alone, and doing its thing
        //    there.
        // AirPods Pro rise like the iPhone's pop-up: almost all the way at
        // once, then a long, gentle glide to a stop, with no bounce. Coming
        // from in front (AirPods) takes a calmer move, like a camera
        // pulling back.
        let rise: Animation
        switch entrance {
        case .caseClip: rise = .timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
        case .caseSpin: rise = .spring(response: 1.0, dampingFraction: 0.9)
        case .caseLid, .still: rise = .spring(response: 0.75, dampingFraction: 0.9)
        }
        step(at: 0.05, rise) { $0.stage = .big }
        if entrance == .caseLid {
            // The lid swings open, then the buds rise out of their wells.
            step(at: 0.62, .spring(response: 0.55, dampingFraction: 0.74)) { $0.flick = true }
            step(at: 0.85, .spring(response: 0.5, dampingFraction: 0.7)) { $0.budsOut = true }
        } else if entrance == .still {
            step(at: 0.6, .spring(response: 0.14, dampingFraction: 0.7)) {
                $0.squash = true
                $0.flick = true
            }
            step(at: 0.72, .spring(response: 0.3, dampingFraction: 0.55)) { $0.squash = false }
        }

        // 2. Down into place; then the buds, the words and the batteries.
        let settle: TimeInterval
        switch entrance {
        case .caseClip: settle = 2.1
        case .caseSpin: settle = 1.7
        case .caseLid: settle = 1.65
        case .still: settle = 1.3
        }
        step(at: settle, .spring(response: 0.62, dampingFraction: 0.86)) { $0.stage = .settled }
        step(at: settle + 0.25, .spring(response: 0.62, dampingFraction: 0.76)) { $0.budsOut = true }
        step(at: settle + 0.2, .spring(response: 0.42, dampingFraction: 0.86)) { $0.title = true }
        step(at: settle + 0.4, .spring(response: 0.4, dampingFraction: 0.55)) { $0.status = true }
        earliestBatteries = settle + 0.5
        if hasLevels {
            step(at: earliestBatteries, .spring(response: 0.6, dampingFraction: 0.85)) { $0.batteries = true }
        }
    }

    /// The levels came in after the card appeared.
    func levelsArrived() {
        guard !batteries else { return }
        if reduceMotion {
            batteries = true
            return
        }
        let wait = max(0, earliestBatteries - Date().timeIntervalSince(appeared))
        step(at: wait, .spring(response: 0.6, dampingFraction: 0.85)) { $0.batteries = true }
    }

    func cancel() {
        steps.forEach { $0.cancel() }
        steps.removeAll()
    }

    private func step(at time: TimeInterval, _ animation: Animation, _ change: @escaping (HeadphoneReveal) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(animation) { change(self) }
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
    }
}
