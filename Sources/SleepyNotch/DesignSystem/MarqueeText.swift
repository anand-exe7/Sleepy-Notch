import SwiftUI

/// A single line of text that scrolls when it's too long to fit, the way
/// Music scrolls long song titles: it rests at the start, glides left until
/// the repeat lines up, and loops. Edges fade instead of cutting hard.
///
/// When it fits, or when the caller passes `animates: false` (paused, Low
/// Power Mode, Reduce Motion), it's an ordinary label truncated with "…".
/// It is always clipped to its own frame, so it can never spill out of the
/// card.
public struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: Double // points per second
    let animates: Bool

    @StateObject private var state = MarqueeState()

    /// Space between the end of the text and its repeat.
    private static let gap: CGFloat = 36
    /// How long it rests at the start of each loop.
    private static let restDuration: TimeInterval = 1.8
    private static let fadeWidth: CGFloat = 12

    public init(_ text: String, font: Font = .system(size: 11, weight: .medium), color: Color = .white.opacity(0.8), speed: Double = 25, animates: Bool = true) {
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
        self.animates = animates
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scrolls = animates && state.textWidth > width + 0.5

            Group {
                if scrolls {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let x = offset(at: timeline.date)
                        HStack(spacing: Self.gap) {
                            label
                            label
                        }
                        .fixedSize()
                        .offset(x: -x)
                        .frame(width: width, alignment: .leading)
                        .mask(edgeFade(width: width, fadesLeading: x > 0))
                    }
                    // Each time scrolling starts, begin from the rest
                    // position rather than mid-loop.
                    .onAppear { state.startDate = Date() }
                } else {
                    label
                        .truncationMode(.tail)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .background(measurement)
        .onChange(of: text) { _ in
            state.startDate = Date()
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
    }

    /// The text's natural one-line width, measured off-screen.
    private var measurement: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TextWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(TextWidthKey.self) { width in
                state.textWidth = width
            }
    }

    /// Rest, then glide one full repeat to the left, then loop. Never moves
    /// right, so the text can't drift away from its column.
    private func offset(at date: Date) -> CGFloat {
        let distance = Double(state.textWidth + Self.gap)
        let cycle = Self.restDuration + distance / max(speed, 1)
        let elapsed = max(0, date.timeIntervalSince(state.startDate))
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        guard phase > Self.restDuration else { return 0 }
        return CGFloat((phase - Self.restDuration) * speed)
    }

    private func edgeFade(width: CGFloat, fadesLeading: Bool) -> LinearGradient {
        let fade = min(0.3, Self.fadeWidth / max(width, 1))
        return LinearGradient(
            stops: [
                .init(color: fadesLeading ? .clear : .black, location: 0),
                .init(color: .black, location: fadesLeading ? fade : 0),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private final class MarqueeState: ObservableObject {
    @Published var textWidth: CGFloat = 0
    /// When the current scroll began. Not published: changing it shouldn't
    /// re-render anything by itself.
    var startDate = Date()
}
