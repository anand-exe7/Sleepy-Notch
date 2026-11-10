import SwiftUI

/// A place to aim a file at, below the notch, while files are being dragged:
/// the very top edge of the screen opens Mission Control, so the pill gives
/// the pointer somewhere to stop before it.
struct DropHintPeekView: View {
    static let contentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text("Drop files here")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drop files here to put them on the shelf")
    }
}
