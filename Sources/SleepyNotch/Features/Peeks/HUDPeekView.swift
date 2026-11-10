import SwiftUI

/// The system's volume, brightness and keyboard backlight, in the notch: a
/// glyph and a level bar, white and still. The bar moves with the level
/// without redrawing anything else, so holding a key stays smooth.
struct HUDPeekView: View {
    let reading: HUDReading

    static let contentHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .frame(width: 24)
            LevelBar(level: reading.muted ? 0 : reading.level)
                .frame(height: 6)
            Text(percent)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var percent: String {
        reading.muted ? "Mute" : "\(Int((reading.level * 100).rounded()))%"
    }

    private var label: String {
        let name: String
        switch reading.kind {
        case .volume: name = "Volume"
        case .brightness: name = "Brightness"
        case .keyboardBacklight: name = "Keyboard backlight"
        }
        return "\(name), \(percent)"
    }

    private var symbol: String {
        switch reading.kind {
        case .volume:
            if reading.muted || reading.level <= 0.001 { return "speaker.slash.fill" }
            if reading.level < 0.34 { return "speaker.wave.1.fill" }
            if reading.level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        case .keyboardBacklight:
            return reading.level <= 0.001 ? "light.min" : "light.max"
        }
    }
}

/// A thin capsule filled to `level`.
private struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(6, proxy.size.width * CGFloat(min(1, max(0, level)))))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }
}

/// Stay Awake, opened from its bubble: what it does and a way to stop it.
struct StayAwakeDetail: View {
    let turnOff: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(Theme.Text.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Staying awake")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text("Your Mac won't sleep on its own")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
            Spacer(minLength: 8)
            Button(action: turnOff) {
                Text("Turn Off")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}
