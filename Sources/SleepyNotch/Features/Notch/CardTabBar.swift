import SwiftUI

enum CardTab {
    case music
    case shelf
    case widgets
    case clipboard
    case controls
}

/// The card's page switch: a small pill centred right under the notch.
/// Icons only; the pages slide with the highlight (see `NotchCardContent`).
/// It fits itself to `available` (width), and if the pages ever outnumber
/// the room, a single button opens a menu of them.
struct CardTabBar: View {
    @ObservedObject var interaction: NotchInteractionState
    let shelfCount: Int
    /// Which pages the card has: the shelf once it holds files, and the
    /// widgets and the clipboard while they're switched on.
    let hasShelf: Bool
    let hasWidgets: Bool
    let hasClipboard: Bool
    let hasControls: Bool
    /// How much width the pill may take.
    let available: CGFloat

    @Namespace private var highlight

    /// The switch between pages: unhurried, and settling without a bounce.
    static let motion = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private struct Page {
        let tab: CardTab
        let icon: String
        let title: String
    }

    private var pages: [Page] {
        var list = [Page(tab: .music, icon: "music.note", title: "Music")]
        if hasShelf {
            list.append(Page(tab: .shelf, icon: "tray.full.fill", title: shelfCount == 1 ? "Shelf, 1 file" : "Shelf, \(shelfCount) files"))
        }
        if hasWidgets { list.append(Page(tab: .widgets, icon: "square.grid.2x2.fill", title: "Widgets")) }
        if hasControls { list.append(Page(tab: .controls, icon: "switch.2", title: "Controls")) }
        if hasClipboard { list.append(Page(tab: .clipboard, icon: "doc.on.clipboard.fill", title: "Clipboard")) }
        return list
    }

    var body: some View {
        let pages = pages
        let button = NotchMetrics.tabButton.width
        if CGFloat(pages.count) * button + CGFloat(pages.count - 1) * 2 + 4 <= available {
            HStack(spacing: 2) {
                ForEach(pages, id: \.tab) { page in tabButton(page) }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        } else {
            menu(pages)
        }
    }

    // MARK: - Buttons

    private func tabButton(_ page: Page) -> some View {
        let isSelected = interaction.tab == page.tab
        return Button {
            guard interaction.tab != page.tab else { return }
            withAnimation(Self.motion) {
                interaction.tab = page.tab
            }
        } label: {
            Image(systemName: page.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
                .frame(width: NotchMetrics.tabButton.width, height: NotchMetrics.tabButton.height)
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(page.title)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Too many pages for icons side by side: the current page's icon, and
    /// a menu with all of them.
    private func menu(_ pages: [Page]) -> some View {
        let current = pages.first { $0.tab == interaction.tab } ?? pages[0]
        let selection = Binding<CardTab>(
            get: { interaction.tab },
            set: { tab in withAnimation(Self.motion) { interaction.tab = tab } }
        )
        return Menu {
            // A picker, so the menu marks the current page itself.
            Picker("Pages", selection: selection) {
                ForEach(pages, id: \.tab) { page in Text(page.title).tag(page.tab) }
            }
            .pickerStyle(.inline)
        } label: {
            // One piece of text holding both glyphs: a menu label draws only
            // the first of two separate views.
            Text("\(Image(systemName: current.icon))  \(Image(systemName: "chevron.down"))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.Text.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // The capsule is drawn outside the menu, which draws its label plain.
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .help("Pages")
        .accessibilityLabel("Pages, \(current.title)")
    }
}
