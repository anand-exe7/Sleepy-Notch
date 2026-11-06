import SwiftUI

enum CardTab {
    case music
    case shelf
    case widgets
    case clipboard
}

/// The card's page switch, shown in the strip right of the camera. Icons
/// only, to fit beside the notch; the pages slide with the highlight (see
/// `NotchCardContent`).
///
/// The strip is only so wide: the camera's cutout is right there, and
/// anything past the strip's left end is hidden behind it. So the bar fits
/// itself to `available`: roomy buttons for two pages, tighter for three,
/// and for four or more a single button that opens a menu of the pages.
struct CardTabBar: View {
    @ObservedObject var interaction: NotchInteractionState
    let shelfCount: Int
    /// Which pages the card has: the shelf once it holds files, and the
    /// widgets and the clipboard while they're switched on.
    let hasShelf: Bool
    let hasWidgets: Bool
    let hasClipboard: Bool
    /// How much width the strip beside the camera leaves for the bar.
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
        if hasClipboard { list.append(Page(tab: .clipboard, icon: "doc.on.clipboard.fill", title: "Clipboard")) }
        return list
    }

    /// The widest button that lets all the pages fit, or nil when even the
    /// narrowest doesn't.
    private func buttonWidth(for count: Int) -> CGFloat? {
        for width in [CGFloat(26), 20] {
            if CGFloat(count) * width + CGFloat(count - 1) * 2 + 4 <= available { return width }
        }
        return nil
    }

    var body: some View {
        let pages = pages
        if let width = buttonWidth(for: pages.count) {
            HStack(spacing: 2) {
                ForEach(pages, id: \.tab) { page in tabButton(page, width: width) }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        } else {
            menu(pages)
        }
    }

    // MARK: - Buttons

    private func tabButton(_ page: Page, width: CGFloat) -> some View {
        let isSelected = interaction.tab == page.tab
        return Button {
            guard interaction.tab != page.tab else { return }
            withAnimation(Self.motion) {
                interaction.tab = page.tab
            }
        } label: {
            Image(systemName: page.icon)
                .font(.system(size: width < 26 ? 10.5 : 11, weight: .medium))
                .foregroundColor(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
                .frame(width: width, height: 20)
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
