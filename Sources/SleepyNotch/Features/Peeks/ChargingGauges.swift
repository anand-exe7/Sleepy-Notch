import SwiftUI

/// A large battery drawn like macOS's own: a rounded outline, a small
/// terminal on the right, and the charge inset from the outline. A glyph
/// (the bolt, a check) can sit centred on it.
///
/// Plain shapes with animatable values: the caller animates `fraction` once
/// and nothing runs afterwards.
struct BatteryGlyph: View {
    /// 0…1 of the charge shown.
    var fraction: Double
    var tint: Color
    /// Opacity of the charge, for low battery's one slow breath.
    var chargeOpacity: Double = 1

    static let size = CGSize(width: 76, height: 36)
    private static let corner: CGFloat = 10
    private static let inset: CGFloat = 3.5

    var body: some View {
        HStack(spacing: 2.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1.5)
                ChargeFill(fraction: fraction)
                    .fill(tint)
                    .opacity(chargeOpacity)
                    .padding(Self.inset)
            }
            .frame(width: Self.size.width, height: Self.size.height)

            // The terminal.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white.opacity(0.32))
                .frame(width: 3, height: 12)
        }
    }
}

/// The charge: a rounded bar `fraction` of the way across. Animatable, so
/// one spring fills it smoothly.
private struct ChargeFill: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(fraction, 0), 1)
        // Never thinner than its own rounded ends, so a sliver reads as charge.
        let width = clamped <= 0 ? 0 : max(rect.height * 0.5, rect.width * CGFloat(clamped))
        let bar = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        return Path(roundedRect: bar, cornerRadius: 6.5, style: .continuous)
    }
}

/// A percentage that counts through the intermediate numbers when animated.
struct CountingPercent: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
            .monospacedDigit()
    }
}
