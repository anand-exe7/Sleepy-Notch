import SwiftUI

/// The closed notch's wings, like the Dynamic Island's compact view: room
/// for the album cover to the left of the camera and dancing bars to the
/// right while there's a song (still while paused), or status — the privacy dots on the left, the
/// battery on the right while it charges. Status takes a side over music.
/// The wings are equal so the notch stays centred; an empty side is just
/// black.
///
/// The cover and bars themselves are drawn by `NotchView`, shared with the
/// open card, so they fly between the two as the card opens and closes.
/// This view lays out the wings and draws the status.
struct StatusWingsView: View {
    let indicators: NotchIndicators
    /// There's a song, playing or paused, and Settings shows it beside the
    /// notch.
    let nowPlaying: Bool
    @ObservedObject var media: PlaybackCoordinator
    let notchWidth: CGFloat
    let height: CGFloat

    /// How wide each wing is for what it holds (see `NotchLayout`).
    static func wingWidth(for indicators: NotchIndicators, nowPlaying: Bool = false) -> CGFloat {
        let leading: CGFloat
        switch (indicators.cameraInUse, indicators.micInUse) {
        case (true, true): leading = 60
        case (false, false): leading = nowPlaying ? nowPlayingWing : 0
        default: leading = 40
        }
        let trailing: CGFloat = indicators.hasTrailing ? 50 : (nowPlaying ? nowPlayingWing : 0)
        return max(leading, trailing)
    }

    private static let nowPlayingWing: CGFloat = 40

    /// Gap between what a wing shows and the notch, so each side hugs the
    /// camera like the Dynamic Island's compact view.
    static let inset: CGFloat = 8

    /// The cover's side length beside a closed notch of `height`.
    static func coverSize(forHeight height: CGFloat) -> CGFloat {
        max(14, height - 12)
    }

    /// The bars beside the closed notch.
    static let barsSize = CGSize(width: 16, height: 13)

    var body: some View {
        let wing = Self.wingWidth(for: indicators, nowPlaying: nowPlaying)
        // Each wing is a fixed-width space with its content laid over it: an
        // empty side would otherwise drop out of the row and shift the rest
        // off centre.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .trailing) {
                    if indicators.hasLeading {
                        PrivacyDots(indicators: indicators)
                            .padding(.trailing, Self.inset)
                    }
                }
            Color.clear.frame(width: notchWidth)
            Color.clear
                .frame(width: wing)
                .overlay(alignment: .leading) {
                    if indicators.hasTrailing {
                        ChargingLevel(level: indicators.chargingLevel)
                            .padding(.leading, Self.inset)
                    }
                }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nowPlaying ? "Now playing: \(media.currentTrack.title)" : "")
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

    var body: some View {
        if let level {
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.Status.charging)
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Charging, \(level) percent")
        }
    }
}
