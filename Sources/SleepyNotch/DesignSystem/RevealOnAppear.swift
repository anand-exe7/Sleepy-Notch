import SwiftUI

extension View {
    /// Fades and lifts this view into place when it appears, a step behind
    /// the views before it (`order` 0, 1, 2…), so a card's rows arrive one
    /// after another as it opens. One-shot; with Reduce Motion it's a fade.
    func revealOnAppear(order: Int) -> some View {
        modifier(RevealOnAppear(order: order))
    }
}

private struct RevealOnAppear: ViewModifier {
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = RevealState()

    func body(content: Content) -> some View {
        let settled = state.isShown || reduceMotion
        return content
            .opacity(state.isShown ? 1 : 0)
            .offset(y: settled ? 0 : 10)
            .blur(radius: settled ? 0 : 3)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05 + Double(order) * 0.06)) {
                    state.isShown = true
                }
            }
    }
}

/// See `ChargingIntro` for why this isn't `@State`.
private final class RevealState: ObservableObject {
    @Published var isShown = false
}
