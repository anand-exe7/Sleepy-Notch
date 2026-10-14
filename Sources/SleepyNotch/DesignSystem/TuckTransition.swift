import SwiftUI

extension AnyTransition {
    /// How content leaves as the notch closes, like the Dynamic Island:
    /// it shrinks up toward the notch, softens and fades, while the shell
    /// closes around it — one motion rather than a cut followed by a snap.
    static var tuckIntoNotch: AnyTransition {
        .modifier(
            active: TuckModifier(progress: 1),
            identity: TuckModifier(progress: 0)
        )
    }
}

private struct TuckModifier: ViewModifier {
    /// 0 in place, 1 fully tucked away.
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.14 * progress, anchor: .top)
            .offset(y: -6 * progress)
            .blur(radius: 5 * progress)
            .opacity(1 - progress)
    }
}
