import SwiftUI

/// The once-per-startup hello: the notch opens and a hand-written "hello"
/// writes itself inside it, like a new Mac greeting you, then the notch
/// closes. Nothing else on the card.
struct WelcomePeekView: View {
    /// Height of the area below the notch, and its corner radius. Close to
    /// the music card's (132 / 40), so it reads as the same surface.
    static let height: CGFloat = 104
    static let bottomRadius: CGFloat = 34

    var body: some View {
        HelloLettering()
            .frame(width: 250, height: 78)
            // Sits a touch above centre, clear of the glass along the bottom.
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hello")
    }
}
