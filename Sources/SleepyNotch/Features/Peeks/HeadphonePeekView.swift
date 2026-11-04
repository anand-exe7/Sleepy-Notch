import SwiftUI
import AppKit

/// Headphones connecting or disconnecting, after the iPhone's AirPods card:
/// the name and status in one line under the notch, and below it each part
/// on its own — left bud, case, right bud — with its battery right under
/// it. Nothing overlaps.
///
/// Connecting, the case drops out of the notch, tipping forward as it lands,
/// and gives a small squash as if its lid flicked open; the buds fly out
/// from behind it to either side, turning to face you; a green check pops in,
/// and the batteries fill. Over-ear headphones swing in from edge-on, tilted
/// back, turning to face you. Disconnecting is the reverse: the buds fly back into the case
/// and everything dims.
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
                opensCase: ProductImages.caseOpeningVideo(for: event.model) != nil
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
        if ProductImages.earbuds(for: event.model) != nil {
            return PartLevels(
                left: battery.left ?? battery.main,
                right: battery.right ?? battery.main,
                chargingCase: battery.caseLevel
            )
        }
        return PartLevels(main: battery.main ?? battery.left ?? battery.right)
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

// MARK: - Parts

/// The product, part by part, each over its battery.
private struct HeadphoneParts: View {
    let event: HeadphoneEvent
    @ObservedObject var reveal: HeadphoneReveal
    let levels: PartLevels

    /// Image sizes and the gap between parts.
    private static let budSize = CGSize(width: 40, height: 58)
    private static let caseSize = CGSize(width: 70, height: 54)
    private static let gap: CGFloat = 26
    private static let artHeight: CGFloat = 62

    /// How far each bud's centre sits from the middle. The batteries use the
    /// same offsets, so each sits exactly under its part.
    private static var budX: CGFloat { caseSize.width / 2 + gap + budSize.width / 2 }
    /// Room for the whole row, with space for the battery labels at the ends.
    private static var rowWidth: CGFloat { 2 * budX + budSize.width + 40 }

    var body: some View {
        Group {
            if let video = ProductImages.caseOpeningVideo(for: event.model) {
                VStack(spacing: 6) {
                    caseOpening(video)
                    groupedBatteries
                        .frame(height: BatteryBar.height)
                }
            } else {
                VStack(spacing: 9) {
                    art
                        .frame(height: Self.artHeight)
                    batteries
                        .frame(height: BatteryBar.height)
                }
            }
        }
        // Dimmed as one picture when disconnecting, so nothing turns
        // see-through.
        .compositingGroup()
        .opacity(reveal.dimmed ? 0.5 : 1)
    }

    // MARK: Apple's case opening

    /// The part of Apple's clip that's used: the closed case, the lid
    /// swinging open, ending on the open case with the buds inside.
    private static let clipStart: Double = 0.3
    private static let clipEnd: Double = 1.85
    private static let videoSize = CGSize(width: 186, height: 98)
    /// The clip's transparent margin under the case is allowed to overlap
    /// the spacing, so the case can be bigger. (The margin above is where
    /// the lid swings up.)
    private static let videoBottomMargin: CGFloat = 12

    /// AirPods Pro: Apple's own 3D case drops out of the notch and its lid
    /// opens. Disconnecting, the case stays shut.
    private func caseOpening(_ video: URL) -> some View {
        ProductVideo(
            url: video,
            start: Self.clipStart,
            end: event.isConnected ? Self.clipEnd : nil,
            delay: HeadphoneReveal.lidOpensAt
        )
        .frame(width: Self.videoSize.width, height: Self.videoSize.height)
        .padding(.bottom, -Self.videoBottomMargin)
        .modifier(DropIn(shown: reveal.hero))
    }

    /// The buds' and the case's batteries in one row under the case, like
    /// the iPhone's card. Buds within a few percent share one reading.
    @ViewBuilder private var groupedBatteries: some View {
        if levels.hasAny {
            HStack(spacing: 22) {
                if let left = levels.left, let right = levels.right, abs(left - right) > 5 {
                    labelled(Self.symbol("airpodpro.left", or: event.model.symbolName), left)
                    labelled(Self.symbol("airpodpro.right", or: event.model.symbolName), right)
                } else if let buds = [levels.left, levels.right].compactMap({ $0 }).min() {
                    labelled(event.model.symbolName, buds)
                }
                if let caseLevel = levels.chargingCase {
                    labelled(Self.symbol("airpodspro.chargingcase.wireless.fill", or: "case.fill"), caseLevel)
                }
            }
        } else {
            Color.clear.frame(width: 1, height: BatteryBar.height)
        }
    }

    private func labelled(_ symbol: String, _ level: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .opacity(reveal.batteries ? 1 : 0)
            BatteryBar(level: level, shown: reveal.batteries)
        }
    }

    private static func symbol(_ name: String, or fallback: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
    }

    // MARK: Art

    @ViewBuilder private var art: some View {
        if let buds = ProductImages.earbuds(for: event.model) {
            ZStack(alignment: .bottom) {
                // Behind the case, so they fly out from behind it.
                bud(buds.left, side: -1)
                bud(buds.right, side: 1)
                if let chargingCase = buds.chargingCase {
                    product(chargingCase)
                        .frame(width: Self.caseSize.width, height: Self.caseSize.height)
                        // The lid flicking open: a quick squash and back.
                        .scaleEffect(x: reveal.squash ? 1.05 : 1, y: reveal.squash ? 0.92 : 1, anchor: .bottom)
                        .modifier(DropIn(shown: reveal.hero))
                }
            }
            .frame(width: Self.rowWidth, height: Self.artHeight, alignment: .bottom)
        } else if let image = ProductImages.overEar(for: event.model) {
            product(image)
                .frame(width: 76, height: Self.artHeight)
                .modifier(SwingIn(shown: reveal.hero))
        } else {
            Image(systemName: event.model.symbolName)
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .frame(height: Self.artHeight)
                .modifier(SwingIn(shown: reveal.hero))
        }
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
            // by then); fading in with the case, they showed through it.
            .opacity(out ? 1 : 0)
    }

    private func product(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
    }

    // MARK: Batteries

    @ViewBuilder private var batteries: some View {
        if ProductImages.earbuds(for: event.model) != nil {
            ZStack {
                bar(levels.left).offset(x: -Self.budX)
                bar(levels.chargingCase)
                bar(levels.right).offset(x: Self.budX)
            }
            .frame(width: Self.rowWidth)
        } else {
            bar(levels.main)
        }
    }

    /// A part's battery, or a placeholder holding its place, so nothing
    /// moves when the levels arrive a moment late.
    @ViewBuilder private func bar(_ level: Int?) -> some View {
        if let level {
            BatteryBar(level: level, shown: reveal.batteries)
        } else {
            Color.clear.frame(width: 1, height: BatteryBar.height)
        }
    }
}

// MARK: - Battery

/// A slim battery bar with the level beside it, like the iPhone's card,
/// centred as a whole under its part.
private struct BatteryBar: View {
    let level: Int
    let shown: Bool

    static let height: CGFloat = 14
    private static let width: CGFloat = 22

    private var tint: Color {
        if level <= 10 { return Theme.Status.critical }
        if level <= 20 { return Theme.Status.warning }
        return Theme.Status.charging
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: shown ? max(4, Self.width * CGFloat(level) / 100) : 0)
            }
            .frame(width: Self.width, height: 7)

            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold))
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

/// Text coming into place: a few points below and clear, then up and solid.
private struct RiseIn: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
    }
}

/// Dropping out of the notch into place, tipped back a little and tipping
/// forward as it lands.
private struct DropIn: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(shown ? 0 : 32), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            .scaleEffect(shown ? 1 : 0.8, anchor: .bottom)
            .offset(y: shown ? 0 : -14)
            .opacity(shown ? 1 : 0)
    }
}

/// Over-ear headphones swinging in: from edge-on and tilted back, turning
/// to face you with a little overshoot, dropping out of the notch.
private struct SwingIn: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(shown ? 0 : 88), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .rotation3DEffect(.degrees(shown ? 0 : -24), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .scaleEffect(shown ? 1 : 0.72)
            .offset(y: shown ? 0 : -18)
            .opacity(shown ? 1 : 0)
    }
}

/// Which parts of the card have arrived. Each step is one spring, started
/// by a one-shot timer. A small object rather than `@State`, which this
/// toolchain can't build (see `NotchInteractionState`).
@MainActor
final class HeadphoneReveal: ObservableObject {
    @Published var hero = false
    @Published var squash = false
    @Published var budsOut = false
    @Published var title = false
    @Published var status = false
    @Published var batteries = false
    @Published var dimmed = false

    private var steps: [DispatchWorkItem] = []
    private var appeared = Date()
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The batteries fill no sooner than this, once the product has landed.
    private var earliestBatteries: TimeInterval = 0.85
    /// When Apple's clip starts playing: once the case has dropped in.
    static let lidOpensAt: TimeInterval = 0.4

    /// - Parameter opensCase: Apple's case-opening clip plays (AirPods Pro);
    ///   the status and batteries wait for the lid.
    func run(isConnected: Bool, hasLevels: Bool, opensCase: Bool = false) {
        cancel()
        appeared = Date()
        earliestBatteries = opensCase ? 1.7 : 0.85
        if reduceMotion {
            hero = true; budsOut = isConnected; title = true; status = true
            batteries = hasLevels; dimmed = !isConnected
            return
        }
        step(at: 0.1, .spring(response: 0.42, dampingFraction: 0.86)) { $0.title = true }

        if isConnected {
            // Swinging in takes a softer, longer spring than dropping in.
            step(at: 0.08, .spring(response: 0.72, dampingFraction: 0.66)) { $0.hero = true }
            // The lid flicks open…
            step(at: 0.4, .spring(response: 0.14, dampingFraction: 0.7)) { $0.squash = true }
            step(at: 0.5, .spring(response: 0.3, dampingFraction: 0.55)) { $0.squash = false }
            // …and the buds fly out, turning to face you as they land.
            step(at: 0.46, .spring(response: 0.62, dampingFraction: 0.76)) { $0.budsOut = true }
            step(at: opensCase ? 1.55 : 0.8, .spring(response: 0.4, dampingFraction: 0.55)) { $0.status = true }
            if hasLevels {
                step(at: earliestBatteries, .spring(response: 0.6, dampingFraction: 0.85)) { $0.batteries = true }
            }
        } else {
            // Everything starts in place, then the buds go home and it dims.
            var start = Transaction()
            start.disablesAnimations = true
            withTransaction(start) { hero = true; budsOut = true }
            step(at: 0.2, .spring(response: 0.4, dampingFraction: 0.7)) { $0.status = true }
            step(at: 0.5, .spring(response: 0.55, dampingFraction: 0.82)) { $0.budsOut = false }
            step(at: 0.62, .easeOut(duration: 0.5)) { $0.dimmed = true }
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
