import SwiftUI
import AppKit

/// The shelf page of the card: dropped files in a row. Drag a file out to
/// put it anywhere (Finder, Mail, Slack), double-click to open, right-click
/// for Open, Show in Finder, AirDrop and Remove.
///
/// The files arrive one after another, rising into place, each lifts a
/// little under the pointer, and they slide aside smoothly as one is added
/// or removed.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let width: CGFloat
    @StateObject private var ui = ShelfViewState()

    /// Nothing on the shelf yet: where files go, and how.
    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Theme.Text.tertiary)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop files on the notch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                Text("Or copy them in Finder and click Paste. Drag them out, or Copy, to use them anywhere.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Zip, convert, combine and compress, applied to what's on the shelf.
    private var transformMenu: some View {
        Menu {
            Button("Zip All") { shelf.zipFiles(shelf.items) }
            Menu("Convert Images") {
                ForEach(ShelfTransform.ImageFormat.allCases, id: \.self) { format in
                    Button(format.rawValue) { shelf.convertImages(shelf.items, to: format) }
                }
            }
            Button("Combine into PDF") { shelf.combineIntoPDF(shelf.items) }
            Button("Compress Images and PDFs") { shelf.compressFiles(shelf.items) }
            if BackgroundRemoval.isAvailable {
                Button("Remove Background") { shelf.removeBackgrounds(shelf.items) }
            }
            Button("Transcribe Audio") { shelf.transcribeAudio(shelf.items) }
        } label: {
            Text(shelf.isWorking ? "Working…" : "Transform")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // The capsule goes outside the menu, which draws its label as plain text.
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .disabled(shelf.isWorking)
        .help("Zip, convert, combine or compress")
        .accessibilityLabel("Transform")
    }

    /// A small capsule button in the header.
    private func headerButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func paste() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            if shelf.pasteFromClipboard() == 0 { ui.flash("No files to paste") }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Shelf")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(ui.note ?? (shelf.items.isEmpty ? "Empty" : shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: ui.note)
                Spacer()
                headerButton("Paste", help: "Paste files copied in Finder", action: paste)
                if !shelf.items.isEmpty {
                    headerButton("Copy", help: "Copy all files to paste anywhere") {
                        shelf.copyToClipboard(shelf.items)
                        ui.flash(shelf.items.count == 1 ? "Copied" : "Copied \(shelf.items.count)")
                    }
                    transformMenu
                    headerButton("Clear", help: "Clear shelf") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { shelf.clear() }
                    }
                }
            }

            if shelf.items.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                            ShelfItemView(item: item, shelf: shelf, arrivalDelay: Double(min(index, 8)) * 0.045)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.86), value: shelf.items.map(\.id))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
        .onAppear { shelf.removeMissingFiles() }
    }
}

/// A short note in the header ("Copied", "No files to paste") that goes
/// away by itself; one one-shot, nothing repeats.
@MainActor
private final class ShelfViewState: ObservableObject {
    @Published var note: String?
    private var clear: DispatchWorkItem?

    func flash(_ text: String) {
        clear?.cancel()
        note = text
        let work = DispatchWorkItem { [weak self] in self?.note = nil }
        clear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
