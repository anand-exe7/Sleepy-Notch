import SwiftUI
import AppKit

/// One file on the shelf: its preview on a soft tile with the name under it.
/// It rises into place when the shelf appears (after `arrivalDelay`), and
/// lifts a little under the pointer.
struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfStore
    /// Kind and size, read by the shelf off the main thread; nil until then.
    var info: ShelfFileInfo?
    var arrivalDelay: Double = 0

    @StateObject private var state = ShelfItemState()

    private static let tile: CGFloat = 86
    private static let cellWidth: CGFloat = 104
    private static let hoverMotion = Animation.spring(response: 0.3, dampingFraction: 0.72)

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(state.isHovered ? 0.12 : 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(state.isHovered ? 0.18 : 0.06), lineWidth: 0.5)
                        )
                    if let thumbnail = state.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                            .padding(10)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(width: Self.tile, height: Self.tile)

                if state.isHovered {
                    Button {
                        withAnimation(ShelfView.motion) {
                            shelf.remove(item)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.65))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    // Inside the tile's corner, clear of the header above.
                    .offset(x: -5, y: 5)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .help("Remove from shelf")
                }
            }

            VStack(spacing: 1) {
                // One line, cut in the middle, so the end of the name (its
                // type) stays visible.
                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(state.isHovered ? Theme.Text.primary : Theme.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(info?.line ?? " ")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.tertiary)
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.2), value: info)
            }
            .frame(width: Self.cellWidth - 8)
        }
        .frame(width: Self.cellWidth)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .scaleEffect(state.isHovered ? 1.05 : 1, anchor: .bottom)
        .offset(y: state.arrived ? (state.isHovered ? -3 : 0) : 14)
        .opacity(state.arrived ? 1 : 0)
        .animation(Self.hoverMotion, value: state.isHovered)
        .onHover { state.isHovered = $0 }
        .onAppear {
            guard !state.arrived else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 + arrivalDelay) {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.8)) { state.arrived = true }
            }
        }
        // Provides the file itself, so dropping on a Finder folder copies it
        // rather than moving the original.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { ShelfActions.open(item.url) }
        .contextMenu {
            Button("Open") { ShelfActions.open(item.url) }
            Button("Show in Finder") { ShelfActions.reveal(item.url) }
            Button("Copy") { shelf.copyToClipboard([item]) }
            Button("AirDrop") { ShelfActions.airDrop([item.url]) }
            Divider()
            Button("Zip") { shelf.zipFiles([item]) }
            if ShelfTransform.isImage(item.url) {
                Menu("Convert To") {
                    ForEach(ShelfTransform.ImageFormat.allCases, id: \.self) { format in
                        Button(format.rawValue) { shelf.convertImages([item], to: format) }
                    }
                }
            }
            if ShelfTransform.isImage(item.url) || ShelfTransform.isPDF(item.url) {
                Button("Compress") { shelf.compressFiles([item]) }
            }
            if ShelfTransform.isImage(item.url) && BackgroundRemoval.isAvailable {
                Button("Remove Background") { shelf.removeBackgrounds([item]) }
            }
            if SpeechTranscription.isAudioOrVideo(item.url) {
                Button("Transcribe") { shelf.transcribeAudio([item]) }
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
        .task(id: item.url) {
            let thumbnail = await ThumbnailLoader.thumbnail(for: item.url, side: Self.tile - 20)
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
