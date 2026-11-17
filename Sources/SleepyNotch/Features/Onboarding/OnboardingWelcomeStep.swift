import SwiftUI

/// Page one: a large hand-written hello, what the app is, and the user's name.
struct OnboardingWelcomeStep: View {
    @ObservedObject var model: OnboardingModel
    let shown: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            HelloLettering(delay: 0.35, colourful: model.preferences.colourfulHello)
                .frame(width: 340, height: 100)
                .id(model.preferences.colourfulHello)
                .rise(0, shown)
            Spacer().frame(height: 26)
            Text("Welcome to Sleepy Notch")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .rise(1, shown)
            Spacer().frame(height: 10)
            Text("Your notch, awake. Music, files, your calendar and what your Mac is doing, right under the camera. Let's set it up together; it takes about a minute.")
                .font(OnboardingStyle.subtitle)
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
                .rise(2, shown)
            Spacer().frame(height: 30)
            nameField
                .rise(3, shown)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(spacing: 8) {
            Text("What should we call you?")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            TextField("Your name", text: $model.name)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(width: 300, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OnboardingStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OnboardingStyle.stroke, lineWidth: 1)
                )
                .onSubmit { model.next() }
            Text("The notch greets you by it when your Mac starts.")
                .font(OnboardingStyle.small)
                .foregroundColor(.white.opacity(0.4))
        }
    }
}
