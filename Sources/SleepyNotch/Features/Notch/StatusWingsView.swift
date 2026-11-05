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
    let primary: ActivityKind?
    @ObservedObject var media: PlaybackCoordinator
    let notchWidth: CGFloat
    let height: CGFloat

    /// How wide each wing is for what the notch shows (see `NotchLayout`).
    /// Music and charging share a width, so the notch keeps its size when
    /// one hands over to the other.
    static func wingWidth(for primary: ActivityKind?, indicators: NotchIndicators) -> CGFloat {
        switch primary {
        case nil: return 0
        case .music, .charging: return 40
        case .privacy: return indicators.cameraInUse && indicators.micInUse ? 60 : 40
        }
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
        return height
    }

    var body: some View {
        let wing = Self.wingWidth(for: primary, indicators: indicators)
        // Each wing is a fixed-width space with its content laid over it: an
        // empty side would otherwise drop out of the row and shift the rest
        // off centre.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .trailing) {
                    switch primary {
                    case .privacy:
                        PrivacyDots(indicators: indicators)
                            .padding(.trailing, Self.inset)
                            .transition(Self.swap)
                    case .charging:
                        MiniBattery(level: indicators.chargingLevel ?? 0)
                            .padding(.trailing, Self.inset)
                            .transition(Self.swap)
                    case .music, nil:
                        EmptyView()
                    }
                }
            Color.clear.frame(width: notchWidth)
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .leading) {
                    if primary == .charging {
                        ChargingLevel(level: indicators.chargingLevel, showsBolt: false)
                            .padding(.leading, Self.inset)
                            .transition(Self.swap)
                    }
                }
        }
        .frame(height: height)
        .animation(NotchView.splitMotion, value: primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(primary == .music ? "Now playing: \(media.currentTrack.title)" : "")
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
        case .charging(let level):
            ChargingRing(level: level)
        case .privacy(let mic, let camera):
            PrivacyGlyphs(indicators: NotchIndicators(micInUse: mic, cameraInUse: camera))
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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - 7
            ZStack {
                Circle()
                    .stroke(Theme.Status.charging.opacity(0.22), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.04, min(1, Double(level) / 100))))
                    .stroke(Theme.Status.charging, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "bolt.fill")
                    .font(.system(size: side * 0.42, weight: .bold))
                    .foregroundColor(Theme.Status.charging)
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Charging, \(level) percent")
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
                        .fill(Theme.Status.charging)
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
                        .foregroundColor(Theme.Status.charging)
                }
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Status.charging)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Charging, \(level) percent")
        }
    }
}
