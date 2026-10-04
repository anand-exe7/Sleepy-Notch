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
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(isSelected ? 0.14 : 0.04)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
