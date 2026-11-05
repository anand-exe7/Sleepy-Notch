import SwiftUI
import AppKit

/// Regular AirPods' case opening, built from Apple's own renders of the
/// case and the buds (see `ProductImages`): Apple ships a 3D clip of this
/// only for AirPods Pro, whose buds have ear tips that regular AirPods don't.
///
/// The case is cut at its seam. The top part is the lid: opening, it tips
/// back on its hinge, so from the front it rises a little and foreshortens,
/// staying joined to the back of the case. The buds stand inside, hidden by
/// the front of the case, and rise in front of the open lid until their
/// heads show above the rim.
///
/// The pieces are cut with plain clipping and moved in 2D, from one fixed
/// bitmap of each render (see `fixed`).
struct RegularAirPodsCase: View {
    let parts: ProductImages.Earbuds
    let chargingCase: NSImage
    let lidOpen: Bool
    let budsUp: Bool
    /// The case's width; its height follows the render.
    var width: CGFloat = 92

    /// Where the lid meets the body, as a fraction of the render's height.
    private static let seam: CGFloat = 0.285

    private var size: CGSize {
        let aspect = chargingCase.size.height / max(chargingCase.size.width, 1)
        return CGSize(width: width, height: width * aspect)
    }

    var body: some View {
        let size = size
        let seamY = size.height * Self.seam
        let budHeight = size.height * 0.62
        ZStack(alignment: .top) {
            // Back to front: the lid (hinged at the back), the buds, then
            // the front of the case they stand in.
            lid(size: size, seamY: seamY, budHeight: budHeight)
            interior(size: size, seamY: seamY, budHeight: budHeight)
            buds(caseSize: size, seamY: seamY, budHeight: budHeight)
            caseImage(size)
                .frame(height: size.height - seamY, alignment: .bottom)
                .clipped()
                .offset(y: seamY)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// Closed, the lid sits on the body. Open, it has tipped back: seen
    /// from the front it's shorter, and its lower edge sits just behind the
    /// buds' heads, still meeting the back of the case.
    private func lid(size: CGSize, seamY: CGFloat, budHeight: CGFloat) -> some View {
        caseImage(size)
            .frame(height: seamY + 0.5, alignment: .top)
            .clipped()
            .scaleEffect(x: lidOpen ? 0.94 : 1, y: lidOpen ? 0.62 : 1, anchor: .bottom)
            .offset(y: lidOpen ? -budHeight * 0.2 : 0)
    }

    /// The inside of the case, seen between the open lid and the rim: pale
    /// plastic, shaded towards the hinge. Only there while the lid is open.
    private func interior(size: CGSize, seamY: CGFloat, budHeight: CGFloat) -> some View {
        let height = budHeight * 0.26
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(white: 0.58), Color(white: 0.8)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: size.width * 0.9, height: height)
            .offset(y: seamY - height + 1)
            .opacity(lidOpen ? 1 : 0)
    }

    /// Two buds side by side, leaning in a touch the way they sit in their
    /// wells. Down, they're hidden by the front of the case; up, their heads
    /// show above the rim.
    private func buds(caseSize: CGSize, seamY: CGFloat, budHeight: CGFloat) -> some View {
        let budWidth = budHeight * parts.left.size.width / max(parts.left.size.height, 1)
        let headTop = budsUp ? seamY - budHeight * 0.32 : seamY + 2
        let gap = caseSize.width * 0.04
        return HStack(spacing: gap) {
            bud(parts.left, lean: 5)
            bud(parts.right, lean: -5)
        }
        .frame(width: budWidth * 2 + gap, height: budHeight)
        .offset(y: headTop)
        .frame(width: caseSize.width)
    }

    private func caseImage(_ size: CGSize) -> some View {
        Self.fixed(chargingCase)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: size.width, height: size.height)
    }

    /// One fixed bitmap of a render. Apple's renders carry more than one
    /// version inside, and SwiftUI switching between them mid-animation
    /// cross-faded the case so the buds showed through it.
    private static func fixed(_ image: NSImage) -> Image {
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Image(nsImage: image)
        }
        let scale = CGFloat(bitmap.width) / max(image.size.width, 1)
        return Image(decorative: bitmap, scale: scale)
    }

    private func bud(_ image: NSImage, lean: Double) -> some View {
        Self.fixed(image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(lean), anchor: .bottom)
    }
}
