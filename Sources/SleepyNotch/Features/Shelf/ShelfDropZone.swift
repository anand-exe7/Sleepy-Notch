import SwiftUI

/// Shown while a file is dragged over the notch.
struct ShelfDropZone: View {
    let existingCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundColor(Color.white.opacity(0.4))

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
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
    }
}
