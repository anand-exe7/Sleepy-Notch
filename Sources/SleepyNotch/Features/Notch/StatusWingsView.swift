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
        if indicators.hasLeading { return 28 }
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

/// Green for the camera, orange for the microphone — the colours iPhone and
/// the Mac's own menu bar use.
struct PrivacyDots: View {
    let indicators: NotchIndicators

    var body: some View {
        HStack(spacing: 4) {
            if indicators.cameraInUse {
                dot(Theme.Status.charging)
            }
            if indicators.micInUse {
                dot(Theme.Status.warning)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .transition(.scale.combined(with: .opacity))
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
