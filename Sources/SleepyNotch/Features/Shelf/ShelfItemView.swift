import SwiftUI
import AppKit

/// One file on the shelf: its preview on a soft tile with the name under it.
/// It rises into place when the shelf appears (after `arrivalDelay`), and
/// lifts a little under the pointer.
struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfStore
    var arrivalDelay: Double = 0

    @StateObject private var state = ShelfItemState()

    private static let tile: CGFloat = 54

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(state.isHovered ? 0.1 : 0.06))
                    if let thumbnail = state.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .padding(6)
                            .transition(.opacity)
                    }
                }
                .frame(width: Self.tile, height: Self.tile)

                if state.isHovered {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            shelf.remove(item)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.black, Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .help("Remove from shelf")
                }
            }

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(state.isHovered ? Theme.Text.primary : Theme.Text.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 66, height: 26, alignment: .top)
        }
        .scaleEffect(state.isHovered ? 1.04 : 1, anchor: .bottom)
        .offset(y: state.arrived ? (state.isHovered ? -2 : 0) : 10)
        .opacity(state.arrived ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isHovered)
        .onHover { state.isHovered = $0 }
        .onAppear {
            guard !state.arrived else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 + arrivalDelay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { state.arrived = true }
            }
        }
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
            let thumbnail = await ThumbnailLoader.thumbnail(for: item.url, side: Self.tile - 12)
            withAnimation(.easeOut(duration: 0.2)) { state.thumbnail = thumbnail }
        }
    }
}

/// See `NotchInteractionState` for why view state lives in an `ObservableObject`.
private final class ShelfItemState: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var isHovered = false
    @Published var arrived = false
}
