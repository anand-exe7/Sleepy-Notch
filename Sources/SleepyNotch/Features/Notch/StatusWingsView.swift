import SwiftUI

/// The closed notch's wings, like the Dynamic Island's compact view. The
/// notch shows one thing at a time in its wings, and anything else splits
/// off into a bubble beside it (see `StatusBubbles`):
/// - a song (playing or paused): the cover left of the camera, the bars
///   right of it;
/// - no song, charging: a small battery left, the level right;
/// - only the camera or mic: the privacy dots left.
/// The wings are equal so the notch stays centred; an empty side is just
/// black.
///
/// The cover and bars themselves are drawn by `NotchView`, shared with the
/// open card, so they fly between the two as the card opens and closes.
/// This view lays out the wings and draws the status.
struct StatusWingsView: View {
    let indicators: NotchIndicators
    /// What the notch shows in its wings (see `ActivityManager`).
    let arrangement: IslandArrangement
    /// Motion is welcome (not Low Power Mode) and the notch can be seen.
    var animates = true
    private var primary: ActivityKind? { arrangement.primary }
    @ObservedObject var media: PlaybackCoordinator
    let notchWidth: CGFloat
    let height: CGFloat

    /// How wide each wing is for what the notch shows (see `NotchLayout`).
    /// Music and charging share a width, so the notch keeps its size when
    /// one hands over to the other.
    static func wingWidth(for arrangement: IslandArrangement, indicators: NotchIndicators) -> CGFloat {
        let dots: CGFloat = indicators.cameraInUse && indicators.micInUse ? 60 : 40
        let base: CGFloat
        switch arrangement.primary {
        case nil: base = 0
        // The camera and mic's dot beside the level needs a little more.
        case .charging:
            switch arrangement.notchBadge {
            case nil: base = 40
            case let badge? where badge.mic && badge.camera: base = 66
            default: base = 52
            }
        case .music: base = 40
        case .timer: base = 52
        // The mic's glyph on the left, its waves (and the camera) on the right.
        case .privacy: base = indicators.micInUse && indicators.cameraInUse ? 58 : 40
        }
        // In the notch, status takes a side and may need it wider.
        let leading: CGFloat = arrangement.leadingStatus ? dots : 0
        let trailing: CGFloat = arrangement.trailingStatus ? 50 : 0
        return max(base, leading, trailing)
    }

    /// Gap between what a wing shows and the notch, so each side hugs the
    /// camera like the Dynamic Island's compact view.
    static let inset: CGFloat = 8

    /// The cover's side length beside a closed notch of `height`.
    static func coverSize(forHeight height: CGFloat) -> CGFloat {
        max(14, height - 12)
    }

    /// The bars beside the closed notch.
    static let barsSize = CGSize(width: 16, height: 13)

    /// A bubble's height beside a closed notch of `height`: a little
    /// shorter than the notch, so it reads as its own piece.
    static func bubbleHeight(forHeight height: CGFloat) -> CGFloat {
        max(18, height - 6)
    }

    /// Round for one glyph, a capsule for the camera and mic together.
    static func bubbleWidth(for face: BubbleFace, height: CGFloat) -> CGFloat {
        if case .privacy(true, true) = face { return height + 16 }
        // The charge with the camera and mic's dot beside the ring.
        return height
    }

    var body: some View {
        let wing = Self.wingWidth(for: arrangement, indicators: indicators)
        // Each wing is a fixed-width space with its content laid over it: an
        // empty side would otherwise drop out of the row and shift the rest
        // off centre.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .trailing) {
                    if arrangement.leadingStatus {
                        PrivacyDots(indicators: indicators)
                            .padding(.trailing, Self.inset)
                            .transition(Self.swap)
                    } else {
                        primaryLeading
                    }
                }
            Color.clear.frame(width: notchWidth)
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .leading) {
                    if arrangement.trailingStatus {
                        ChargingLevel(level: indicators.chargingLevel)
                            .padding(.leading, Self.inset)
                            .transition(Self.swap)
                    } else if primary == .charging {
                        HStack(spacing: 5) {
                            ChargingLevel(level: indicators.chargingLevel, showsBolt: false)
                            if let badge = arrangement.notchBadge {
                                PrivacyBadgeDots(badge: badge)
                                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                            }
                        }
                        .padding(.leading, Self.inset)
                        .transition(Self.swap)
                    } else if primary == .timer, let session = arrangement.timer {
                        TimerWingText(session: session)
                            .padding(.leading, Self.inset)
                            .transition(Self.swap)
                    } else if primary == .privacy && indicators.micInUse {
                        // The voice waves sit across the camera from the mic,
                        // like a call on the Dynamic Island.
                        HStack(spacing: 8) {
                            MicWaveView(height: 12, animates: animates)
                            if indicators.cameraInUse {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.Status.charging)
                                    .accessibilityLabel("Camera in use")
                            }
                        }
                        .padding(.leading, Self.inset)
                        .transition(Self.swap)
                    }
                }
        }
        .frame(height: height)
        .animation(NotchView.splitMotion, value: arrangement)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(primary == .music ? "Now playing: \(media.currentTrack.title)" : "")
    }

    /// The left wing's content when no status has taken it.
    @ViewBuilder
    private var primaryLeading: some View {
        switch primary {
        case .privacy:
            Image(systemName: indicators.micInUse ? "mic.fill" : "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(indicators.micInUse ? Theme.Status.warning : Theme.Status.charging)
                .padding(.trailing, Self.inset)
                .transition(Self.swap)
                .accessibilityLabel(indicators.micInUse ? "Microphone in use" : "Camera in use")
        case .charging:
            MiniBattery(level: indicators.chargingLevel ?? 0)
                .padding(.trailing, Self.inset)
                .transition(Self.swap)
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .padding(.trailing, Self.inset)
                .transition(Self.swap)
        case .music, nil:
            EmptyView()
        }
    }

    /// One wing's content handing over to another's: the old leaves at
    /// once, the new grows in a beat later, so the two never overlap.
    private static let swap = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.6).combined(with: .opacity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.14)),
        removal: .opacity.animation(.easeOut(duration: 0.1))
    )
}

/// What's in the bubbles beside the closed notch: the camera and mic on the
/// left, the charge on the right. Laid out over the whole panel and placed
/// where `NotchBubble` puts each bubble, at the same scale, so the content
/// rides along as the bubble splits off and melts back in.
struct StatusBubbles: View {
    let leading: NotchBubble
    let trailing: NotchBubble
    /// Where each bubble measures from, in the panel (see `NotchBubble.anchor`).
    let leadingEdge: CGFloat
    let trailingEdge: CGFloat
    /// What each side shows, kept after its activity is gone so a bubble
    /// still shows it while it melts back in.
    let faces: [NotchSide: BubbleFace]
    /// A click on a bubble that's showing.
    let onTap: (NotchSide) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            place(leading, side: .leading, edge: leadingEdge)
            place(trailing, side: .trailing, edge: trailingEdge)
        }
    }

    @ViewBuilder
    private func face(_ side: NotchSide) -> some View {
        switch faces[side] {
        case .charging(let level, let badge):
            let bubble = side == .leading ? leading : trailing
            // While the camera or mic is on, a thin edge in their colour runs
            // round the bubble, and the ring steps in a little to make room.
            ZStack {
                ChargingRing(level: level, shown: bubble.isShown, inset: badge == nil ? 7 : 10)
                if let badge {
                    Circle()
                        .strokeBorder(PrivacyBadgeDots.tint(for: badge), lineWidth: 1.5)
                        .padding(0.5)
                        .transition(.opacity)
                        .accessibilityLabel(PrivacyBadgeDots.label(for: badge))
                }
            }
            .animation(.easeOut(duration: 0.3), value: badge)
        case .privacy(let mic, let camera):
            PrivacyGlyphs(indicators: NotchIndicators(micInUse: mic, cameraInUse: camera))
        case .timer(let start, let end):
            TimerRing(start: start, end: end)
                .padding(5)
        case nil:
            EmptyView()
        }
    }

    private static let glyphsIn = Animation.easeOut(duration: 0.16).delay(0.1)
    private static let glyphsOut = Animation.easeOut(duration: 0.08)

    private func place(_ bubble: NotchBubble, side: NotchSide, edge: CGFloat) -> some View {
        let width = max(bubble.width, bubble.height)
        return face(side)
            .frame(width: width, height: bubble.height)
            .contentShape(Capsule())
            .onTapGesture { onTap(side) }
            .allowsHitTesting(bubble.isShown)
            // The glyphs wait until the bubble is mostly out of the notch,
            // and are gone before it slides back in, so they never sit over
            // the notch's own content.
            .opacity(bubble.isShown ? 1 : 0)
            .animation(bubble.isShown ? Self.glyphsIn : Self.glyphsOut, value: bubble.isShown)
            .scaleEffect(bubble.scale)
            .offset(
                x: bubble.centerX(side: side, bodyEdge: edge) - width / 2,
                y: bubble.centerY - bubble.height / 2
            )
            .accessibilityHidden(!bubble.isShown)
    }
}

/// The charge as a bubble: a green ring filled to the level around a bolt,
/// like a Live Activity's minimal view. Drawn once; nothing moves.
struct ChargingRing: View {
    let level: Int
    /// The bubble is out: the ring fills up from empty to the level.
    var shown = true
    /// How much smaller than the bubble the ring is.
    var inset: CGFloat = 7

    @StateObject private var fill = RingFill()

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - inset
            ChargeArc(fraction: fill.fraction, glyphSize: side * 0.42)
                .frame(width: side, height: side)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { fill.show(level: level, from: shown ? nil : 0) }
        .onChange(of: shown) { shown in
            // Each time it splits off, it fills up again from empty.
            if shown { fill.show(level: level, from: 0) }
        }
        .onChange(of: level) { fill.show(level: $0, from: nil) }
        .accessibilityElement()
        .accessibilityLabel("Charging, \(level) percent")
    }
}

/// The ring's fill, animated once per change: from empty as the bubble
/// splits off, then to each new level as it charges. Nothing runs between.
private final class RingFill: ObservableObject {
    @Published var fraction: Double = 0

    func show(level: Int, from start: Double?) {
        let target = max(0.04, min(1, Double(level) / 100))
        if let start {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { fraction = start }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.1).delay(0.15)) { self.fraction = target }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.8)) { fraction = target }
        }
    }
}

/// The ring and bolt, coloured by how full it is: red when low, through
/// orange and yellow, to green. Animatable, so the colour changes with the
/// line as it grows.
private struct ChargeArc: View, Animatable {
    var fraction: Double
    let glyphSize: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        let tint = ChargeTint.color(for: fraction)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.fill")
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundColor(tint)
        }
    }
}

/// The charge's colour: red when low, orange, yellow, then green from
/// about 80%. The system's own colours, blended between.
enum ChargeTint {
    private static let stops: [(at: Double, color: NSColor)] = [
        (0.0, .systemRed), (0.2, .systemRed), (0.4, .systemOrange), (0.6, .systemYellow), (0.8, .systemGreen),
    ]

    static func color(for fraction: Double) -> Color {
        let f = min(1, max(0, fraction))
        guard let upper = stops.firstIndex(where: { $0.at >= f }), upper > 0 else {
            return Color(nsColor: f <= 0 ? stops[0].color : stops[stops.count - 1].color)
        }
        let a = stops[upper - 1], b = stops[upper]
        let t = CGFloat((f - a.at) / (b.at - a.at))
        guard let from = a.color.usingColorSpace(.sRGB), let to = b.color.usingColorSpace(.sRGB) else {
            return Color(nsColor: b.color)
        }
        return Color(
            red: Double(from.redComponent + (to.redComponent - from.redComponent) * t),
            green: Double(from.greenComponent + (to.greenComponent - from.greenComponent) * t),
            blue: Double(from.blueComponent + (to.blueComponent - from.blueComponent) * t)
        )
    }

    static func color(forLevel level: Int) -> Color {
        color(for: Double(level) / 100)
    }
}

/// The camera and mic glyphs on their own, for the bubble (the bubble is
/// their background).
struct PrivacyGlyphs: View {
    let indicators: NotchIndicators

    var body: some View {
        HStack(spacing: 5) {
            if indicators.cameraInUse {
                Image(systemName: "video.fill")
                    .foregroundColor(Theme.Status.charging)
            }
            if indicators.micInUse {
                Image(systemName: "mic.fill")
                    .foregroundColor(Theme.Status.warning)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .accessibilityElement()
        .accessibilityLabel(indicators.cameraInUse && indicators.micInUse
            ? "Camera and microphone in use"
            : indicators.cameraInUse ? "Camera in use" : "Microphone in use")
    }
}

/// The camera and mic riding on the charge: beside the level in the
/// notch's wing, their glyphs, green for the camera and orange for the mic
/// (the colours macOS uses). On the charge's bubble they're its edge instead.
struct PrivacyBadgeDots: View {
    let badge: PrivacyBadge

    /// Orange whenever the mic is on: it's the more private of the two.
    static func tint(for badge: PrivacyBadge) -> Color {
        badge.mic ? Theme.Status.warning : Theme.Status.charging
    }

    static func label(for badge: PrivacyBadge) -> String {
        badge.camera && badge.mic
            ? "Camera and microphone in use"
            : badge.camera ? "Camera in use" : "Microphone in use"
    }

    var body: some View {
        HStack(spacing: 4) {
            if badge.camera {
                Image(systemName: "video.fill").foregroundColor(Theme.Status.charging)
            }
            if badge.mic {
                Image(systemName: "mic.fill").foregroundColor(Theme.Status.warning)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .accessibilityElement()
        .accessibilityLabel(Self.label(for: badge))
    }
}

/// A small battery for the charging wing, filled to the level, with the
/// bolt over it.
struct MiniBattery: View {
    let level: Int

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ChargeTint.color(forLevel: level))
                        .frame(width: max(2, proxy.size.width * CGFloat(min(100, max(0, level))) / 100))
                }
                .padding(2)
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: 1.5, height: 4.5)
        }
        .accessibilityHidden(true)
    }
}

/// What's using the camera and microphone, as one small tinted pill: a
/// green camera and an orange mic — the colours iPhone and the Mac's own
/// menu bar use — like the Dynamic Island's recording indicator.
struct PrivacyDots: View {
    let indicators: NotchIndicators

    var body: some View {
        HStack(spacing: 5) {
            if indicators.cameraInUse {
                glyph("video.fill", Theme.Status.charging)
            }
            if indicators.micInUse {
                glyph("mic.fill", Theme.Status.warning)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(tint.opacity(0.2)))
        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: indicators)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    /// Orange whenever the mic is on — it's the more private of the two.
    private var tint: Color {
        indicators.micInUse ? Theme.Status.warning : Theme.Status.charging
    }

    private func glyph(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private var label: String {
        switch (indicators.cameraInUse, indicators.micInUse) {
        case (true, true): return "Camera and microphone in use"
        case (true, false): return "Camera in use"
        case (false, true): return "Microphone in use"
        case (false, false): return ""
        }
    }
}

struct ChargingLevel: View {
    let level: Int?
    /// The wing has the battery beside it already.
    var showsBolt = true

    var body: some View {
        if let level {
            HStack(spacing: 2) {
                if showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ChargeTint.color(forLevel: level))
                }
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(ChargeTint.color(forLevel: level))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Charging, \(level) percent")
        }
    }
}
