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
                 detail: "The song playing, its cover and controls. Always the first page.", isOn: nil),
            Page(id: "shelf", symbol: "tray.full.fill", title: "Shelf",
                 detail: "Drag files onto the notch to keep them close, then drag them out anywhere.", isOn: $preferences.shelf),
            Page(id: "calendar", symbol: "calendar", title: "Calendar",
                 detail: "This month, and the day's events from your Mac's Calendar.", isOn: $preferences.widgets),
            Page(id: "controls", symbol: "switch.2", title: "Controls",
                 detail: "Dark Mode, Mute, Stay Awake and Focus, one click each.", isOn: $preferences.controls),
            Page(id: "clipboard", symbol: "doc.on.clipboard.fill", title: "Clipboard",
                 detail: "What you copied lately, to copy again. Kept in memory only.", isOn: $preferences.clipboardHistory),
        ]
    }

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "rectangle.stack.fill",
                eyebrow: "Card pages",
                title: "Choose your card's pages",
                subtitle: "Hover the notch and it opens into a card. Music is always its first page; add any of these beside it. You switch pages with the small pill under the notch.",
                shown: shown
            )
            ScreenPreview(notchWidth: 300, notchHeight: 64, cornerRadius: 14) {
                pill.padding(.top, 30)
            }
            .frame(width: 420, height: 92)
            .rise(2, shown)
            HStack(spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    HoverReader { hovering in tile(page, hovering: hovering) }
                        .rise(3 + index, shown)
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

    private func tile(_ page: Page, hovering: Bool) -> some View {
        let locked = page.isOn == nil
        let on = page.isOn?.wrappedValue ?? true
        return Button {
            page.isOn?.wrappedValue.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(on ? .black : .white.opacity(0.75))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(on ? Color.white : Color.white.opacity(0.08))
                        )
                    Spacer(minLength: 0)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(width: 18, height: 18)
                    } else {
                        SelectionMark(selected: on)
                    }
                }
                Spacer().frame(height: 14)
                Text(page.title)
                    .font(OnboardingStyle.heading)
                    .foregroundColor(.white)
                Spacer().frame(height: 4)
                Text(page.detail)
                    .font(OnboardingStyle.small)
                    .foregroundColor(.white.opacity(0.52))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(locked ? "Always on" : on ? "On" : "Off")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(on ? 0.75 : 0.35))
            }
            .padding(12)
            .frame(width: 128, height: 196, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on || hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        on && !locked ? OnboardingStyle.selectedStroke : Color.white.opacity(hovering && !locked ? 0.22 : 0.1),
                        lineWidth: on && !locked ? 2 : 1
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
