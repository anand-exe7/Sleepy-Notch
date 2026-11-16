import SwiftUI
import AppKit

/// The shelf page of the card, opened big: dropped files as large previews
/// in a row, each with its name and kind/size. Drag a file out to put it
/// anywhere (Finder, Mail, Slack), double-click to open, right-click for
/// Open, Show in Finder, AirDrop, transforms and Remove.
///
/// The files rise into place one after another, a dropped file falls in
/// from above, each lifts a little under the pointer, and the row slides
/// aside smoothly as one is added or removed. Nothing ticks: sizes are read
/// once per file, off the main thread.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    let width: CGFloat
    @StateObject private var ui = ShelfViewState()

    private static let inset: CGFloat = 24
    private static let iconButton: CGFloat = 28
    static let motion = Animation.spring(response: 0.42, dampingFraction: 0.84)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, Self.inset)

            if shelf.items.isEmpty {
                emptyState
                    .padding(.horizontal, Self.inset)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                files
                    .transition(.opacity)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: width, alignment: .leading)
        .animation(Self.motion, value: shelf.items.isEmpty)
        .onAppear {
            shelf.removeMissingFiles()
            ui.checkClipboard()
            ui.measure(shelf.items.map(\.url))
        }
        .onChange(of: shelf.items.map(\.url)) { ui.measure($0) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Shelf")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.Text.primary)
            Text(ui.note ?? summary)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(ui.note == nil ? Theme.Text.tertiary : Theme.Text.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: ui.note)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                if ui.clipboardHasFiles && !shelf.items.isEmpty {
                    iconButton("clipboard", help: "Paste files copied in Finder", action: paste)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if !shelf.items.isEmpty {
                    iconButton("doc.on.doc", help: "Copy all files to paste anywhere") {
                        shelf.copyToClipboard(shelf.items)
                        ui.flash(shelf.items.count == 1 ? "Copied" : "Copied \(shelf.items.count) files")
                    }
                    iconButton("trash", help: "Clear shelf") {
                        withAnimation(Self.motion) { shelf.clear() }
                    }
                }
            }
            .animation(Self.motion, value: ui.clipboardHasFiles)
        }
        .frame(height: Self.iconButton)
    }

    /// "Empty", "1 file · 2.4 MB", "5 files · 18 MB".
    private var summary: String {
        let count = shelf.items.count
        guard count > 0 else { return "Empty" }
        let files = count == 1 ? "1 file" : "\(count) files"
        guard let bytes = ui.totalBytes, bytes > 0 else { return files }
        return "\(files) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    /// A round icon button in the header; the name is in its tooltip.
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: Self.iconButton, height: Self.iconButton)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func paste() {
        withAnimation(Self.motion) {
            if shelf.pasteFromClipboard() == 0 { ui.flash("No files to paste") }
        }
        ui.checkClipboard()
    }

    // MARK: - Files

    /// Runs to the card's edges, so a file past the last one peeks in from
    /// the side and says there's more to scroll to.
    private var files: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                    ShelfItemView(
                        item: item,
                        shelf: shelf,
                        info: ui.info[item.url],
                        arrivalDelay: Double(min(index, 8)) * 0.045
                    )
                    .transition(.asymmetric(
                        insertion: .offset(y: -22).combined(with: .scale(scale: 0.7)).combined(with: .opacity),
                        removal: .scale(scale: 0.75).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, Self.inset - 8)
            .padding(.top, 2)
            // A few files sit centred; more than fit run from the left
            // edge and scroll.
            .frame(minWidth: width, alignment: .center)
            .animation(Self.motion, value: shelf.items.map(\.id))
        }
    }

    /// Nothing on the shelf yet: one wide drop zone saying where files go,
    /// with Paste right in it.
    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop files here")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text("Or copy files in Finder and paste")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: paste) {
                HStack(spacing: 5) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Paste")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 13)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .fixedSize()
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Paste files copied in Finder")
        }
        .padding(.horizontal, 18)
        // A fixed height, in the card's dark upper part: stretched to the
        // bottom, its words sat in the see-through edge.
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                )
        )
    }
}

/// A file's kind and size, for the line under its name.
struct ShelfFileInfo: Equatable {
    /// "PDF", "HEIC", "Folder", "Application".
    let kind: String
    /// Nil for folders and apps, whose size would mean walking them.
    let bytes: Int64?

    var line: String {
        guard let bytes else { return kind }
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    /// Read off the main thread: one metadata lookup per file.
    static func read(_ url: URL) -> ShelfFileInfo {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isApplicationKey, .fileSizeKey])
        if values?.isApplication == true || url.pathExtension.lowercased() == "app" {
            return ShelfFileInfo(kind: "Application", bytes: nil)
        }
        if values?.isDirectory == true && values?.isPackage != true {
            return ShelfFileInfo(kind: "Folder", bytes: nil)
        }
        let ext = url.pathExtension.uppercased()
        return ShelfFileInfo(kind: ext.isEmpty ? "File" : ext, bytes: values?.fileSize.map(Int64.init))
    }
}

/// The shelf page's own state: a short note in the header ("Copied") that
/// goes away by itself, whether the clipboard holds files (read when the
/// page appears, nothing is watched), and each file's kind and size.
@MainActor
private final class ShelfViewState: ObservableObject {
    @Published var note: String?
    @Published var clipboardHasFiles = false
    @Published var info: [URL: ShelfFileInfo] = [:]
    @Published var totalBytes: Int64?
    private var clear: DispatchWorkItem?

    func flash(_ text: String) {
        clear?.cancel()
        note = text
        let work = DispatchWorkItem { [weak self] in self?.note = nil }
        clear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func checkClipboard() {
        let has = ShelfStore.clipboardHasFiles()
        if has != clipboardHasFiles { clipboardHasFiles = has }
    }

    /// Reads what's missing, on a background queue, and publishes it in
    /// one change.
    func measure(_ urls: [URL]) {
        let missing = urls.filter { info[$0] == nil }
        guard !missing.isEmpty else { return total(urls) }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let read = missing.map { ($0, ShelfFileInfo.read($0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (url, value) in read { self.info[url] = value }
                self.total(urls)
            }
        }
    }

    private func total(_ urls: [URL]) {
        let sizes = urls.compactMap { info[$0]?.bytes }
        let sum: Int64? = sizes.isEmpty ? nil : sizes.reduce(0, +)
        if sum != totalBytes { totalBytes = sum }
    }
}
