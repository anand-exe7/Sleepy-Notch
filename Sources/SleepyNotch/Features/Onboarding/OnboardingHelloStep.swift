import SwiftUI

/// Page two: the ink of the startup hello, each written live in a sample
/// notch, and whether it plays at every startup.
struct OnboardingHelloStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: HUDPreferences
    let shown: Bool

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "hand.wave.fill",
                eyebrow: "The hello",
                title: model.firstName.map { "Hi \($0). How should the notch say hello?" } ?? "How should the notch say hello?",
                subtitle: "When your Mac starts, the notch opens and writes \u{201C}hello\u{201D}, then greets you. Pick its ink; click one to watch it again.",
                shown: shown
            )
            HStack(spacing: 16) {
                card(colourful: true, take: model.colourTake)
                    .rise(2, shown)
                card(colourful: false, take: model.whiteTake)
                    .rise(3, shown)
            }
            OnboardingToggle(
                title: "Say hello every time the Mac starts",
                detail: "Off: the notch stays quiet at startup.",
                isOn: $preferences.welcomeAtStartup
            )
            .frame(width: 400)
            .rise(4, shown)
        }
    }

    private func card(colourful: Bool, take: Int) -> some View {
        OptionCard(
            title: colourful ? "Colourful" : "Frosted white",
            detail: colourful ? "Apple's six colours along the pen line." : "A soft white line, quiet and clean.",
            selected: preferences.colourfulHello == colourful,
            action: { model.chooseHello(colourful: colourful) }
        ) {
            ScreenPreview(notchWidth: 230, notchHeight: 112) {
                VStack(spacing: 3) {
                    HelloLettering(delay: shown ? 0.5 : 60, colourful: colourful)
                        .frame(width: 168, height: 50)
                    WrittenCaption(
                        text: WelcomePeekView.caption(for: model.name),
                        delay: shown ? 2.1 : 60,
                        font: .systemFont(ofSize: 10.5, weight: .medium)
                    )
                    .frame(width: 200, height: 14)
                }
                .padding(.top, 22)
                // A new take writes it again from the start.
                .id("\(take)-\(shown)")
            }
            .frame(width: 290, height: 150)
        }
        .frame(width: 310)
    }
}
