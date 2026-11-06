import SwiftUI

enum CardTab {
    case music
    case shelf
    case widgets
}

/// Music / Shelf switch, shown in the strip right of the camera once the
/// shelf has something on it. Icons only, to fit beside the notch; the shelf
/// itself says how many files it holds. The highlight slides from one to the
/// other, and the pages slide with it (see `NotchCardContent`).
struct CardTabBar: View {
    @ObservedObject var interaction: NotchInteractionState
    let shelfCount: Int
    /// Which pages the card has: the shelf once it holds files, and the
    /// widgets while they're switched on.
    let hasShelf: Bool
    let hasWidgets: Bool

    @Namespace private var highlight

    /// The switch between pages: unhurried, and settling without a bounce.
    static let motion = Animation.spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.music, icon: "music.note", help: "Music")
            if hasShelf {
                tabButton(.shelf, icon: "tray.full.fill", help: shelfCount == 1 ? "Shelf, 1 file" : "Shelf, \(shelfCount) files")
            }
            if hasWidgets {
                tabButton(.widgets, icon: "square.grid.2x2.fill", help: "Widgets")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func tabButton(_ tab: CardTab, icon: String, help: String) -> some View {
        let isSelected = interaction.tab == tab
        return Button {
            guard interaction.tab != tab else { return }
            withAnimation(Self.motion) {
                interaction.tab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
                .frame(width: 26, height: 20)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
