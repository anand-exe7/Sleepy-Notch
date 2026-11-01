import SwiftUI

/// "Copied", with a glimpse of what: the first line of text, the link's
/// site, a thumbnail of the image, or the file.
struct CopyPeekView: View {
    let preview: ClipboardPreview

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Text.secondary)
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Text.tertiary)
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder private var thumbnail: some View {
        switch preview.kind {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .files(let files):
            if let first = files.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                glyph("doc")
            }
        case .link:
            glyph("link")
        case .text:
            glyph("text.alignleft")
        }
    }

    private func glyph(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.1))
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
            )
    }

    private var summary: String {
        switch preview.kind {
        case .text(let text):
            return text
        case .link(let url):
            return url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url.absoluteString
        case .image(let image):
            return "Image · \(Int(image.size.width)) × \(Int(image.size.height))"
        case .files(let files):
            if files.count == 1, let first = files.first { return first.lastPathComponent }
            return "\(files.count) items"
        }
    }
}
