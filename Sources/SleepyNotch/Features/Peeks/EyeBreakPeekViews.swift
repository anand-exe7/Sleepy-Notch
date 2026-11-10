import SwiftUI

private final class Entrance: ObservableObject {
    @Published var shown = false

    func play() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.shown = true }
    }
}

/// The 20-20-20 reminder: an eye settles into place once, with the rule in
/// plain words. Nothing moves after that.
struct EyeBreakPeekView: View {
    static let contentHeight: CGFloat = 72

    @StateObject private var entrance = Entrance()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)

    var body: some View {
        let shown = entrance.shown || reduceMotion
        HStack(spacing: 14) {
            Image(systemName: "eye.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(Theme.Text.primary)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : Self.rise, value: shown)
            VStack(alignment: .leading, spacing: 2) {
                Text("Eye break")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text("Look 20 feet away for 20 seconds")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
            .offset(y: shown ? 0 : 8)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : Self.rise.delay(0.15), value: shown)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 6)
        .onAppear { entrance.play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Eye break. Look 20 feet away for 20 seconds.")
    }
}

/// A line of text from a script (see `LocalBridge`).
struct MessagePeekView: View {
    let text: String

    static let contentHeight: CGFloat = 46

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.Text.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 4)
            .accessibilityLabel(text)
    }
}
