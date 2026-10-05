import SwiftUI

/// Shown while a file is dragged over the notch.
struct ShelfDropZone: View {
    let existingCount: Int

    @StateObject private var glow = DropZoneGlow()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(glow.isBright ? 0.07 : 0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundColor(Color.white.opacity(glow.isBright ? 0.5 : 0.25))

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .offset(y: glow.isBright ? 2 : 0)
                Text("Drop files here")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(existingCount == 0
                     ? "They'll wait on the shelf"
                     : "Adds to the \(existingCount) on the shelf")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 2)
        .onAppear {
            // Only exists while a drag hovers the notch, so the repeat ends
            // with the drag.
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glow.isBright = true
            }
        }
    }
}

private final class DropZoneGlow: ObservableObject {
    @Published var isBright = false
}
