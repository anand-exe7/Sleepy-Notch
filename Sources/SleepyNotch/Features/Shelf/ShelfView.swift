import SwiftUI
import AppKit

/// The shelf tab of the card: dropped files in a row. Drag a file out to put
/// it anywhere (Finder, Mail, Slack), double-click to open, right-click for
/// Open, Show in Finder, AirDrop and Remove.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Shelf")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.tertiary)
                Spacer()
                headerButton("Clear shelf", icon: "trash") {
                    shelf.clear()
                }
            }
            .revealOnAppear(order: 0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shelf.items) { item in
                        ShelfItemView(item: item, shelf: shelf)
                    }
                }
            }
            .revealOnAppear(order: 1)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 2)
        .frame(width: width, alignment: .leading)
    }

    private func headerButton(_ help: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PressScaleButtonStyle())
        .contentShape(Rectangle().inset(by: -6))
        .help(help)
    }
}
