import SwiftUI

/// Album art at a given size, or a plain grey tile with a note while there's
/// no artwork yet — the same neutral placeholder Music uses.
struct CoverArtView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    var placeholderIcon: String = "music.note"

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.16)
                    Image(systemName: placeholderIcon)
                        .font(.system(size: size * 0.36, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
    }
}
