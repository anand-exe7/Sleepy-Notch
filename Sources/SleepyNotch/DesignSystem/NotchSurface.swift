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
/// top stays pure black, then dissolves into glass. The camera sits in a
/// display cutout, so anything lighter than black near it shows the cutout
/// as a black block; keeping the top black lets the card and the hardware
/// notch read as one piece. Peeks and the closed notch are solid black.
///
/// The glass and the black fade are drawn once at the open card's full
/// size and never resize; the moving shape cuts them out, the same way the
/// card's content is masked. Glass doesn't follow SwiftUI's springs — it
/// jumped to its final size and lingered after the notch had closed — and
/// this way nothing about it is recalculated while the notch moves. As the
/// card grows it simply reveals more of itself: black first, then glass
/// at the bottom; closing hides it again in the same order.
struct NotchSurface: View {
    /// The shape and size right now, animated by the caller.
    let shape: NotchShape
    let size: CGSize
    /// The open card's shape and size, which the glass is drawn at.
    let cardShape: NotchShape
    let cardSize: CGSize
    let finish: NotchFinish
    /// True while the card is open.
    let showsGlass: Bool
    /// True unless the card is open. Peeks reach down into the glass area
    /// and stay solid black, and on the way closed the cover darkens the
    /// glass as the shape shrinks over it.
    let coversGlass: Bool

    /// Where black starts giving way to glass, and where it's all glass, as
    /// fractions of the open card's height. A tall blend, so the black
    /// dissolves into the glass gradually rather than meeting it at a seam.
    private static let blendStart: CGFloat = 0.36
    private static let blendEnd: CGFloat = 0.84

    var body: some View {
        if #available(macOS 26, *), finish == .glass {
            ZStack(alignment: .top) {
                ZStack {
                    // Only there while the card is open or closing, so the
                    // closed notch and peeks cost nothing to draw.
                    if showsGlass {
                        Color.clear
                            // Darkened so white text and controls stay
                            // readable over a bright desktop.
                            .glassEffect(.regular.tint(Color.black.opacity(0.32)), in: cardShape)
                            .environment(\.colorScheme, .dark)
                            // Leaves once the close has finished. Until then
                            // the shrinking shape hides it.
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .opacity.animation(.linear(duration: 0.01).delay(0.5))
                            ))
                    }
                    // The black over the top of the glass.
                    Rectangle().fill(Self.blackFade)
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .mask(alignment: .top) {
                    shape.frame(width: size.width, height: size.height)
                }

                shape
                    .fill(Theme.notchFill)
                    .frame(width: size.width, height: size.height)
                    .opacity(coversGlass ? 1 : 0)
            }
            .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
        } else {
            shape
                .fill(Theme.notchFill)
                .frame(width: size.width, height: size.height)
        }
    }

    /// Black on top dissolving to clear, along an S-curve so the seam has
    /// no visible edge.
    private static let blackFade: LinearGradient = {
        // Smootherstep (6t⁵ − 15t⁴ + 10t³) sampled finely: it starts and
        // ends with zero slope *and* zero curvature, so neither end of the
        // blend shows a line where it begins or finishes.
        let steps = 16
        var stops: [Gradient.Stop] = [.init(color: .black, location: 0)]
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let amount = t * t * t * (t * (t * 6 - 15) + 10)
            let location = blendStart + (blendEnd - blendStart) * CGFloat(t)
            stops.append(.init(color: .black.opacity(1 - amount), location: location))
        }
        stops.append(.init(color: .clear, location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }()
}
