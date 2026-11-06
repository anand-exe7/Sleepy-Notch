import SwiftUI

/// The open card when nothing is playing and the shelf is empty: a short
/// line on what the notch can hold, and two quick actions. It replaces the
/// old "No Track Playing" card, which the notch never opened to show.
struct IdleCardView: View {
    let metrics: NotchMetrics
    let startDemo: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
            Text("Nothing playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text("Drop files here to keep them on the shelf")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.tertiary)
                .lineLimit(1)

            HStack(spacing: 8) {
                action("Play Demo", icon: "play.fill", perform: startDemo)
                action("Settings", icon: "gearshape.fill", perform: openSettings)
            }
            .padding(.top, 7)
        }
        .frame(width: metrics.cardWidth, height: NotchMetrics.cardBodyHeight - 6)
        .padding(.top, metrics.notchHeight + 2)
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.Text.primary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}
