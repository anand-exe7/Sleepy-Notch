import SwiftUI

/// The once-per-startup hello: the notch opens, a hand-written "hello"
/// writes itself inside it, like a new Mac greeting you, and a quiet line
/// follows under it. Then the notch closes.
struct WelcomePeekView: View {
    /// Height of the area below the notch, and its corner radius. Close to
    /// the music card's (132 / 40), so it reads as the same surface.
    static let height: CGFloat = 128
    static let bottomRadius: CGFloat = 36
    /// The glass rises to just below the notch's own height, so the word is
    /// written over smoky Liquid Glass while the strip by the camera stays
    /// black.
    static let glassFrom: CGFloat = 0.3

    static let caption = "Welcome to your Mac"
    /// The caption starts as the pen reaches the end of the o, so the two
    /// read as one motion.
    private static let captionDelay: TimeInterval = 2.05

    var body: some View {
        VStack(spacing: 6) {
            HelloLettering()
                .frame(width: 250, height: 74)
            WrittenCaption(text: Self.caption, delay: Self.captionDelay)
                .frame(width: 260, height: 18)
        }
        // Sits a touch above centre, clear of the rounded bottom.
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hello. \(Self.caption).")
    }
}
