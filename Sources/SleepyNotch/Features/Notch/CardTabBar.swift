import SwiftUI

enum CardTab {
    case music
    case shelf
}

/// Music / Shelf switch, shown in the strip right of the camera once the
/// shelf has something on it. Icons only, to fit beside the notch; the shelf
/// itself says how many files it holds.
struct CardTabBar: View {
    @ObservedObject var interaction: NotchInteractionState
    let shelfCount: Int

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.music, icon: "music.note", help: "Music")
            tabButton(.shelf, icon: "tray.full.fill", help: shelfCount == 1 ? "Shelf, 1 file" : "Shelf, \(shelfCount) files")
        }
    }

    private func tabButton(_ tab: CardTab, icon: String, help: String) -> some View {
        let isSelected = interaction.tab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                interaction.tab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
                .frame(width: 24, height: 22)
            .background(Capsule().fill(Color.white.opacity(isSelected ? 0.12 : 0)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
