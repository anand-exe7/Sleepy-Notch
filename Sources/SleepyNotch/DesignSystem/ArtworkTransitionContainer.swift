import SwiftUI

/// Swaps its content with `style` whenever `key` changes.
///
/// Flip turns the cover in 3D and needs room past its edges, so it isn't
/// clipped. Blur-morph stays inside the cover's rounded shape, so its
/// enlarged cover never spills over the title next to it.
struct ArtworkTransitionContainer<Content: View>: View {
    let key: String
    let style: ArtworkTransitionStyle
    let size: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stack = ZStack {
            content()
                .id(key)
                .transition(style.transition(size: size, reduceMotion: reduceMotion))
        }
        .frame(width: size, height: size)
        .animation(.default, value: key)

        if style == .flip {
            stack
        } else {
            stack.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
