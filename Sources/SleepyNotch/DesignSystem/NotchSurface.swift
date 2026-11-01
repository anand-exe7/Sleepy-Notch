import SwiftUI

/// What the notch's body is made of.
enum NotchFinish: String, CaseIterable {
    /// Black where it meets the hardware notch, melting into Liquid Glass
    /// below it.
    case glass
    /// Solid black all the way down, like the hardware cutout.
    case black

    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .black: "Black"
        }
    }

    var summary: String {
        switch self {
        case .glass: "Black at the top, melting into glass along the bottom."
        case .black: "Solid black, like the notch itself."
        }
    }

    /// Glass needs macOS 26. Older systems always get black.
    var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return self == .black
    }
}

/// The notch's body, drawn in the chosen finish.
///
/// With glass, only the open card gets it, and only along the bottom: the
/// top stays pure black, then blends into glass for the lower third. The
/// camera sits in a display cutout, so anything lighter than black near it
/// shows the cutout as a black block; keeping the top black lets the card
/// and the hardware notch read as one piece. Peeks and the closed notch are
/// solid black, with no glass edge peeking out under the menu bar.
///
/// The glass view only exists while the card is open, so the closed notch
/// costs nothing to draw.
struct NotchSurface: View {
    let shape: NotchShape
    let finish: NotchFinish
    /// True while the card is open. Peeks and the closed notch stay black.
    let showsGlass: Bool

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the height from the top. A tall blend, so the black
    /// dissolves into the glass gradually rather than meeting it at a seam.
    private static let blendStart: CGFloat = 0.36
    private static let blendEnd: CGFloat = 0.84

    var body: some View {
        if #available(macOS 26, *), finish == .glass {
            ZStack {
                if showsGlass {
                    Color.clear
                        // Darkened so white text and controls stay readable
                        // over a bright desktop.
                        .glassEffect(.regular.tint(Color.black.opacity(0.32)), in: shape)
                        .environment(\.colorScheme, .dark)
                        // Faded out at the top, so its bright rim never shows
                        // beside the black.
                        .mask(Self.blend(glass: true))
                        .transition(Self.glassTransition)
                }

                // The black top. Below the blend it's clear, so the glass
                // shows through.
                shape.fill(Self.blend(glass: false))

                // Solid black while the glass is away. Opening, it fades out
                // as the glass fades in, so the bottom melts from black into
                // glass; closing, it comes straight back.
                if !showsGlass {
                    shape
                        .fill(Theme.notchFill)
                        .transition(Self.blackTransition)
                }
            }
        } else {
            shape.fill(Theme.notchFill)
        }
    }

    /// Black on top fading to clear (or, for the glass's mask, the reverse),
    /// along an S-curve so the seam has no visible edge.
    private static func blend(glass: Bool) -> LinearGradient {
        // Smootherstep (6t⁵ − 15t⁴ + 10t³) sampled finely: it starts and
        // ends with zero slope *and* zero curvature, so neither end of the
        // blend shows a line where it begins or finishes.
        let steps = 16
        var stops: [Gradient.Stop] = [.init(color: .black.opacity(glass ? 0 : 1), location: 0)]
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let amount = t * t * t * (t * (t * 6 - 15) + 10)
            let location = blendStart + (blendEnd - blendStart) * CGFloat(t)
            stops.append(.init(color: .black.opacity(glass ? amount : 1 - amount), location: location))
        }
        stops.append(.init(color: .black.opacity(glass ? 1 : 0), location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// The glass melts in once the card has started to open, and is gone
    /// quickly when it closes.
    private static let glassTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.34).delay(0.1)),
        removal: .opacity.animation(.easeIn(duration: 0.12))
    )

    private static let blackTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.12)),
        removal: .opacity.animation(.easeOut(duration: 0.34).delay(0.1))
    )
}
