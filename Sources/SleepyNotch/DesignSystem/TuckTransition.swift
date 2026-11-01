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

extension AnyTransition {
    /// How content arrives as the notch opens: the reverse of
    /// `tuckIntoNotch`. It starts small, blurred and tucked up against the
    /// notch, then comes into focus as it drops into place, so it reads as
    /// flowing out of the notch rather than fading in on top of it.
    static var meltOutOfNotch: AnyTransition {
        .modifier(
            active: MeltModifier(progress: 1),
            identity: MeltModifier(progress: 0)
        )
    }
}

private struct MeltModifier: ViewModifier {
    /// 0 in place, 1 still inside the notch.
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 - 0.1 * progress, y: 1 - 0.16 * progress, anchor: .top)
            .offset(y: -8 * progress)
            .blur(radius: 10 * progress)
            .opacity(1 - progress)
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
