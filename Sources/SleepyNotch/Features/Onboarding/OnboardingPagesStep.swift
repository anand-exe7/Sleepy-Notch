import SwiftUI

/// Page three: the card's pages. Music is always there; any of the other
/// four can sit beside it. A sample of the page pill under the notch shows
/// the choice as it's made.
struct OnboardingPagesStep: View {
    @ObservedObject var preferences: HUDPreferences
    let shown: Bool

    private struct Page: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let isOn: Binding<Bool>?
    }

    private var pages: [Page] {
        [
            Page(id: "music", symbol: "music.note", title: "Music",
                 detail: "The song and its controls", isOn: nil),
            Page(id: "shelf", symbol: "tray.full.fill", title: "Shelf",
                 detail: "Keep dropped files close at hand", isOn: $preferences.shelf),
            Page(id: "calendar", symbol: "calendar", title: "Calendar",
                 detail: "This month and today's events", isOn: $preferences.widgets),
            Page(id: "controls", symbol: "switch.2", title: "Controls",
                 detail: "Dark Mode, Mute, Focus and more", isOn: $preferences.controls),
            Page(id: "clipboard", symbol: "doc.on.clipboard.fill", title: "Clipboard",
                 detail: "Recent copies, never saved", isOn: $preferences.clipboardHistory),
        ]
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                step: .pages,
                title: "Choose your card's pages",
                subtitle: "Hover the notch to open the card. Music comes first; add pages beside it.",
                shown: shown
            )
            ScreenPreview(notchWidth: 300, notchHeight: 62, cornerRadius: 14) {
                pill.padding(.top, 28)
            }
            .frame(width: 600, height: 92)
            .rise(2, shown)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    HoverReader { hovering in row(page, hovering: hovering) }
                        .rise(3 + index / 2, shown)
                }
            }
        }
    }

    /// The pill as it will look: Music, then each page that's on.
    private var pill: some View {
        HStack(spacing: 4) {
            ForEach(pages.filter { $0.isOn?.wrappedValue ?? true }) { page in
                Image(systemName: page.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(page.id == "music" ? .black : .white.opacity(0.8))
                    .frame(width: 30, height: 22)
                    .background(Capsule().fill(page.id == "music" ? Color.white : Color.clear))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .animation(OnboardingStyle.select, value: preferences.shelf)
        .animation(OnboardingStyle.select, value: preferences.widgets)
        .animation(OnboardingStyle.select, value: preferences.controls)
        .animation(OnboardingStyle.select, value: preferences.clipboardHistory)
    }

    private func row(_ page: Page, hovering: Bool) -> some View {
        let locked = page.isOn == nil
        let on = page.isOn?.wrappedValue ?? true
        return Button {
            page.isOn?.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: page.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(on ? .black : .white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(on ? Color.white : Color.white.opacity(0.08))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .font(OnboardingStyle.heading)
                        .foregroundColor(.white.opacity(on ? 1 : 0.75))
                    Text(page.detail)
                        .font(OnboardingStyle.small)
                        .foregroundColor(on ? OnboardingStyle.secondaryText : OnboardingStyle.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if locked {
                    Text("Always on")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(OnboardingStyle.tertiaryText)
                } else {
                    SelectionMark(selected: on)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on || hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        on && !locked ? Color.white.opacity(0.5) : Color.white.opacity(hovering && !locked ? 0.2 : 0.08),
                        lineWidth: 1
                    )
            )
            .lifted(hovering && !locked)
            .animation(OnboardingStyle.select, value: on)
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(locked)
        .accessibilityLabel("\(page.title), \(locked ? "always on" : on ? "on" : "off")")
    }
}
