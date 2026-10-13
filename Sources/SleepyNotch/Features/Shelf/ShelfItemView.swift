import SwiftUI
import AppKit

struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfStore

    @StateObject private var state = ShelfItemState()

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = state.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.scrim)
                    }
                }
                .frame(width: 46, height: 46)

                if state.isHovered {
                    Button { shelf.remove(item) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .background(Circle().fill(Color.black))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Remove from shelf")
                }
            }

            Text(item.name)
                .font(.system(size: 10))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 26, alignment: .top)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(state.isHovered ? 0.08 : 0))
        )
        .onHover { state.isHovered = $0 }
        // Provides the file itself, so dropping on a Finder folder copies it
        // rather than moving the original.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { ShelfActions.open(item.url) }
        .contextMenu {
            Button("Open") { ShelfActions.open(item.url) }
            Button("Show in Finder") { ShelfActions.reveal(item.url) }
            Button("AirDrop") { ShelfActions.airDrop([item.url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
        .task(id: item.url) {
            state.thumbnail = await ThumbnailLoader.thumbnail(for: item.url, side: 46)
        }
    }
}

/// See `NotchInteractionState` for why view state lives in an `ObservableObject`.
private final class ShelfItemState: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var isHovered = false
}
