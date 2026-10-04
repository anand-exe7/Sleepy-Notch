import SwiftUI

/// Album art at a given size, or a tinted gradient placeholder when there's
/// no artwork yet.
struct CoverArtView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    let tint: Color
    var placeholderIcon: String = "music.note"

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            tint.opacity(0.55),
                            tint.opacity(0.2),
                            Color(red: 0.06, green: 0.06, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: placeholderIcon)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
