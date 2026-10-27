import SwiftUI

/// How album art changes when the track does. Each style is a one-shot
/// transition (well under a second), then the art is still again.
enum ArtworkTransitionStyle: String, CaseIterable {
    /// The old cover blurs and shrinks while the new one springs in sharp.
    case blurMorph
    /// The old cover turns away in 3D and the new one turns in.
    case flip

    var title: String {
        switch self {
        case .blurMorph: return "Blur-morph"
        case .flip: return "Flip"
        }
    }

    /// One line for the Settings window, under the picker.
    var summary: String {
        switch self {
        case .blurMorph: return "The old cover blurs into the new one."
        case .flip: return "The cover turns over to the next one."
        }
    }

    /// - Parameter size: the artwork's width, so a 16pt mini cover and a
    ///   48pt card cover travel and blur proportionally.
    /// - Parameter reduceMotion: falls back to a plain crossfade.
    func transition(size: CGFloat, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: 0.25))
        }
        switch self {
        case .blurMorph:
            let blur = size * 0.25
            return .asymmetric(
                insertion: .modifier(
                    active: MorphEffect(blur: blur, scale: 1.2, opacity: 0),
                    identity: MorphEffect(blur: 0, scale: 1, opacity: 1)
                ).animation(.spring(response: 0.5, dampingFraction: 0.7)),
                removal: .modifier(
                    active: MorphEffect(blur: blur, scale: 0.8, opacity: 0),
                    identity: MorphEffect(blur: 0, scale: 1, opacity: 1)
                ).animation(.easeIn(duration: 0.3))
            )
        case .flip:
            return .asymmetric(
                insertion: .modifier(
                    active: FlipEffect(angle: -90),
                    identity: FlipEffect(angle: 0)
                ).animation(.spring(response: 0.42, dampingFraction: 0.72).delay(0.2)),
                removal: .modifier(
                    active: FlipEffect(angle: 90),
                    identity: FlipEffect(angle: 0)
                ).animation(.easeIn(duration: 0.2))
            )
        }
    }
}

private struct FlipEffect: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .opacity(abs(angle) >= 90 ? 0 : 1)
    }
}

private struct MorphEffect: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}
