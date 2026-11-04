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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Shelf")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                    .contentTransition(.opacity)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                        shelf.clear()
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Text.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .help("Clear shelf")
                .accessibilityLabel("Clear shelf")
            }

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
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .frame(width: width, alignment: .leading)
        .onAppear { shelf.removeMissingFiles() }
    }
}
