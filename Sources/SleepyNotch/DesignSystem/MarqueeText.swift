import SwiftUI

/// Scrolling marquee text for titles too long to fit.
/// Battery-safe: scrolls only when the text overflows *and* the caller passes
/// `animates` (playing, and motion allowed); otherwise it's a still label.
public struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: Double // points per second
    let animates: Bool
    
    @StateObject private var state = MarqueeState()
    
    public init(_ text: String, font: Font = .system(size: 11, weight: .medium), color: Color = .white.opacity(0.8), speed: Double = 25, animates: Bool = true) {
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
        self.animates = animates
    }

    private var isScrolling: Bool {
        state.shouldAnimate && animates
    }
    
    public var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isScrolling)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                
                HStack(spacing: 0) {
                    // Measure the text width
                    textView
                        .fixedSize()
                        .background(
                            GeometryReader { textGeo in
                                Color.clear.onAppear {
                                    state.textWidth = textGeo.size.width
                                    state.containerWidth = containerWidth
                                    state.shouldAnimate = state.textWidth > containerWidth
                                }
                                .onChange(of: text) { _ in
                                    state.textWidth = textGeo.size.width
                                    state.shouldAnimate = state.textWidth > containerWidth
                                    state.startTime = now
                                }
                            }
                        )
                    
                    if state.shouldAnimate {
                        // Gap between repeated text
                        Spacer().frame(width: 40)
                        textView.fixedSize()
                    }
                }
                .offset(x: isScrolling ? offsetForTime(now) : 0)
            }
            .clipped()
        }
        // Resuming starts from the beginning of the text rather than jumping
        // to wherever the clock says it would have scrolled to.
        .onChange(of: animates) { animating in
            if animating { state.startTime = Date.timeIntervalSinceReferenceDate }
        }
    }
    
    private var textView: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
    }
    
    private func offsetForTime(_ now: TimeInterval) -> CGFloat {
        let totalScrollWidth = state.textWidth + 40 // text + gap
        let elapsed = now - state.startTime
        let offset = CGFloat(elapsed * speed).truncatingRemainder(dividingBy: totalScrollWidth)
        return -offset
    }
}

private final class MarqueeState: ObservableObject {
    @Published var textWidth: CGFloat = 0
    @Published var containerWidth: CGFloat = 0
    @Published var shouldAnimate: Bool = false
    var startTime: TimeInterval = Date.timeIntervalSinceReferenceDate
}
