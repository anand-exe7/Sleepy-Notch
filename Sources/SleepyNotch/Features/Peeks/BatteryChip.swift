import SwiftUI

/// "L ▭ 92%": a label, a small battery, and the level. Orange when low.
struct BatteryChip: View {
    let label: String
    let level: Int

    private var tint: Color {
        level <= 20 ? Theme.Status.warning : Theme.Text.primary
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.Text.tertiary)
            MiniBattery(level: level, tint: tint)
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(tint)
        }
        .fixedSize()
    }
}

private struct MiniBattery: View {
    let level: Int
    let tint: Color

    private static let bodyWidth: CGFloat = 22
    private static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(
                        width: max(2, (Self.bodyWidth - Self.inset * 2) * CGFloat(level) / 100),
                        height: 7
                    )
                    .offset(x: Self.inset)
            }
            .frame(width: Self.bodyWidth, height: 11)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
    }
}
