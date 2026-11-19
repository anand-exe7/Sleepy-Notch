import SwiftUI

/// Page one: a large hand-written hello, what the app is, and the user's name.
struct OnboardingWelcomeStep: View {
    @ObservedObject var model: OnboardingModel
    let shown: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HelloLettering(delay: 0.35, colourful: model.preferences.colourfulHello)
                .frame(width: 300, height: 88)
                .id(model.preferences.colourfulHello)
                .rise(0, shown)
            Spacer().frame(height: 28)
            Text("Welcome to Sleepy Notch")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
                .rise(1, shown)
            Spacer().frame(height: 8)
            Text("Music, files and what your Mac is doing, right under the camera.")
                .font(OnboardingStyle.subtitle)
                .foregroundColor(OnboardingStyle.secondaryText)
                .multilineTextAlignment(.center)
                .rise(2, shown)
            Spacer().frame(height: 34)
            nameField
                .rise(3, shown)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nameField: some View {
        VStack(spacing: 7) {
            Text("What should we call you?")
                .font(OnboardingStyle.label)
                .foregroundColor(OnboardingStyle.secondaryText)
            TextField("Your name", text: $model.name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(width: 280, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(OnboardingStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .onSubmit { model.next() }
            Text("The notch greets you by name when your Mac starts.")
                .font(OnboardingStyle.small)
                .foregroundColor(OnboardingStyle.tertiaryText)
        }
    }
}
