import SwiftUI
import AppKit

/// The shelf tab of the card: dropped files in a row. Drag a file out to put
/// it anywhere (Finder, Mail, Slack), double-click to open, right-click for
/// more.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Shelf")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
                Text(shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Text.tertiary)
                Spacer()
                headerButton("AirDrop all", icon: "dot.radiowaves.left.and.right") {
                    ShelfActions.airDrop(shelf.items.map(\.url))
                }
                headerButton("Clear shelf", icon: "trash") {
                    shelf.clear()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shelf.items) { item in
                        ShelfItemView(item: item, shelf: shelf)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 2)
        .frame(width: width, alignment: .leading)
    }

    private func headerButton(_ help: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.scrim))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -6))
        .help(help)
    }
}

private struct ShelfItemView: View {
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
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 24, alignment: .top)
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

/// See `ChargingIntro` for why view state lives in an `ObservableObject`.
private final class ShelfItemState: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var isHovered = false
}

@MainActor
enum ShelfActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }
}

/// Shown while a file is dragged over the notch.
struct ShelfDropZone: View {
    let existingCount: Int

    @StateObject private var glow = DropZoneGlow()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(glow.isBright ? 0.07 : 0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundColor(Color.white.opacity(glow.isBright ? 0.5 : 0.25))

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .offset(y: glow.isBright ? 2 : 0)
                Text("Drop files here")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Text.primary)
                Text(existingCount == 0
                     ? "They'll wait on the shelf"
                     : "Adds to the \(existingCount) on the shelf")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Text.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 2)
        .onAppear {
            // Only exists while a drag hovers the notch, so the repeat ends
            // with the drag.
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glow.isBright = true
            }
        }
    }
}

private final class DropZoneGlow: ObservableObject {
    @Published var isBright = false
}
