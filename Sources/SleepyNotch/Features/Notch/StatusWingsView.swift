import SwiftUI

/// The closed notch's wings, like the Dynamic Island's compact view: the
/// privacy dots to the left of the camera, the battery to the right while
/// it charges. The wings are equal so the notch stays centred; an empty side
/// is just black.
struct StatusWingsView: View {
    let indicators: NotchIndicators
    let notchWidth: CGFloat
    let height: CGFloat

    /// How wide each wing is for what it holds (see `NotchLayout`).
    static func wingWidth(for indicators: NotchIndicators) -> CGFloat {
        if indicators.hasTrailing { return 50 }
        if indicators.hasLeading { return 44 }
        return 0
    }

    var body: some View {
        let wing = Self.wingWidth(for: indicators)
        HStack(spacing: 0) {
            PrivacyDots(indicators: indicators)
                .frame(width: wing)
            Color.clear.frame(width: notchWidth)
            ChargingLevel(level: indicators.chargingLevel)
                .frame(width: wing)
        }
        .frame(height: height)
    }
}

/// What's using the camera and microphone: a green camera and an orange
/// mic, each a small filled badge — the colours iPhone and the Mac's own
/// menu bar use. Both at once overlap slightly, camera in front.
struct PrivacyDots: View {
    let indicators: NotchIndicators
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: -size * 0.22) {
            if indicators.cameraInUse {
                badge("video.fill", Theme.Status.charging)
                    .zIndex(1)
            }
            if indicators.micInUse {
                badge("mic.fill", Theme.Status.warning)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: indicators.cameraInUse)
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: indicators.micInUse)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.black.opacity(0.82))
        }
        .frame(width: size, height: size)
        // A black ring keeps the two apart where they overlap.
        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
        .transition(.scale(scale: 0.2).combined(with: .opacity))
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
