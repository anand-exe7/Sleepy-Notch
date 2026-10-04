import SwiftUI

enum CardTab {
    case music
    case shelf
}

/// Music / Shelf switch, shown in the strip beside the camera once the shelf
/// has something on it.
struct CardTabBar: View {
    @ObservedObject var interaction: NotchInteractionState
    let shelfCount: Int

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.music, icon: "music.note", help: "Music")
            tabButton(.shelf, icon: "tray.full.fill", help: "Shelf", badge: shelfCount)
        }
    }

    private func tabButton(_ tab: CardTab, icon: String, help: String, badge: Int? = nil) -> some View {
        let isSelected = interaction.tab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                interaction.tab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(isSelected ? 0.12 : 0)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
    }
}
