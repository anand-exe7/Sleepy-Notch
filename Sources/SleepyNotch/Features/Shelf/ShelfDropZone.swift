import SwiftUI
import AppKit

/// The big drop zone: opens as files are dragged near the notch, the size of
/// the shelf it turns into once they're dropped.
///
/// The files being dragged show as a little fan of their own previews (up to
/// three, "+N" for the rest). Near the notch the fan rests closed; with the
/// files over the zone it opens out and lifts, the border firms up and the
/// line reads "Release to drop". Everything moves on springs and plays once:
/// nothing loops while it waits.
struct ShelfDropZone: View {
    let existingCount: Int
    /// The files are over the zone itself, not just near the notch.
    let isOver: Bool
    @EnvironmentObject private var drag: FileDragMonitor

    static let motion = Animation.spring(response: 0.36, dampingFraction: 0.72)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(isOver ? 0.085 : 0.04))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isOver ? 0.5 : 0.2),
                    style: StrokeStyle(lineWidth: isOver ? 1.5 : 1.2, dash: [7, 6])
                )

            VStack(spacing: 16) {
                DragFan(files: drag.draggedFiles, extra: max(0, drag.draggedCount - drag.draggedFiles.count), open: isOver)
                    .frame(height: 86)
                VStack(spacing: 4) {
                    Text(isOver ? "Release to drop" : "Drop on the Shelf")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                        .contentTransition(.opacity)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .offset(y: 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .animation(Self.motion, value: isOver)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drop files here to put them on the shelf")
    }

    private var subtitle: String {
        let count = drag.draggedCount
        let files = count == 1 ? "1 file" : "\(count) files"
        if existingCount == 0 { return count > 0 ? "\(files) · they'll wait on the shelf" : "They'll wait on the shelf" }
        return count > 0 ? "\(files) · joins the \(existingCount) on the shelf" : "Joins the \(existingCount) on the shelf"
    }
}

/// Up to three previews of the dragged files, fanned like cards in a hand.
private struct DragFan: View {
    let files: [URL]
    let extra: Int
    let open: Bool
    @StateObject private var state = DragFanState()

    private static let tile: CGFloat = 66

    var body: some View {
        let count = max(files.count, 1)
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element) { index, url in
                let slot = CGFloat(index) - CGFloat(count - 1) / 2
                preview(url)
                    .rotationEffect(.degrees(Double(slot) * (open ? 13 : 6)), anchor: .bottom)
                    .offset(x: slot * (open ? 34 : 12), y: abs(slot) * (open ? 6 : 2))
                    .zIndex(Double(index == count / 2 ? 10 : index))
            }
            if files.isEmpty { preview(nil) }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.black)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.95)))
                    .offset(x: Self.tile / 2 + (open ? 44 : 20), y: -Self.tile / 2 + 4)
                    .zIndex(20)
            }
        }
        .scaleEffect(open ? 1.06 : 1)
        .offset(y: state.arrived ? (open ? -4 : 0) : -26)
        .opacity(state.arrived ? 1 : 0)
        .animation(ShelfDropZone.motion, value: open)
        .onAppear {
            state.load(files, side: Self.tile)
            guard !state.arrived else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.74).delay(0.08)) { state.arrived = true }
        }
        .onChange(of: files) { state.load($0, side: Self.tile) }
    }

    private func preview(_ url: URL?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.16))
            if let url, let image = state.images[url] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(7)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.Text.tertiary)
            }
        }
        .frame(width: Self.tile, height: Self.tile)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

/// The fan's previews: the Finder icon at once, then the Quick Look
/// thumbnail when it's ready. See `NotchInteractionState` for why view
/// state lives in an `ObservableObject`.
@MainActor
private final class DragFanState: ObservableObject {
    @Published var images: [URL: NSImage] = [:]
    @Published var arrived = false
    private var loaded: [URL] = []

    func load(_ urls: [URL], side: CGFloat) {
        guard urls != loaded else { return }
        loaded = urls
        for url in urls where images[url] == nil {
            images[url] = NSWorkspace.shared.icon(forFile: url.path)
            Task { [weak self] in
                let thumbnail = await ThumbnailLoader.thumbnail(for: url, side: side)
                self?.images[url] = thumbnail
            }
        }
    }
}
