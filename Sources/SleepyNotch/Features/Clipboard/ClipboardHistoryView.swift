import SwiftUI

/// The clipboard page of the card: what was copied lately. Click a row to
/// copy it again; right-click to remove it.
struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistory
    let width: CGFloat

    static let rowHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(history.entries.count == 1 ? "1 item" : "\(history.entries.count) items")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                Spacer()
                if !history.entries.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { history.clear() }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.Text.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel("Clear clipboard history")
                }
            }

            if history.entries.isEmpty {
                Text("Things you copy show up here.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(history.entries) { entry in
                            row(entry)
                        }
                    }
                }
                .frame(height: Self.rowHeight * 3.6)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: width, alignment: .leading)
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        let copied = history.justCopied == entry.id
        return Button { history.copy(entry) } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : entry.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(copied ? Theme.Text.primary : Theme.Text.tertiary)
                    .frame(width: 16)
                Text(copied ? "Copied" : entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(copied ? 0.14 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .contextMenu {
            Button("Copy") { history.copy(entry) }
            Button("Remove") { history.remove(entry) }
        }
        .help(entry.title)
    }
}
