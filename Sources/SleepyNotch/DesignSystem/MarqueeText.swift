import SwiftUI
import QuartzCore

/// A single line of text that scrolls when it's too long to fit, the way
/// Music scrolls long song titles: it rests at the start, glides left until
/// the repeat lines up, and loops. Edges fade instead of cutting hard.
///
/// When it fits, or when the caller passes `animates: false` (paused, Low
/// Power Mode, Reduce Motion), it's an ordinary label truncated with "…".
/// It is always clipped to its own frame, so it can never spill out of the
/// card.
///
/// Battery: the text is drawn once into an image and the scroll is one
/// looping Core Animation animation, handed to the window server, so this
/// app does no work per frame. (Redrawn in SwiftUI 30 times a second, a long
/// title cost about 5% CPU and 18 wake-ups a second for as long as the card
/// stayed open.)
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: Double // points per second
    let animates: Bool
    /// Where the text sits when it fits (it scrolls from the leading edge).
    var alignment: Alignment = .leading

    @StateObject private var state = MarqueeState()

    /// Space between the end of the text and its repeat.
    fileprivate static let gap: CGFloat = 36
    /// How long it rests at the start of each loop.
    fileprivate static let restDuration: TimeInterval = 1.8
    fileprivate static let fadeWidth: CGFloat = 12

    init(_ text: String, font: Font = .system(size: 11, weight: .medium), color: Color = .white.opacity(0.8), speed: Double = 25, animates: Bool = true, alignment: Alignment = .leading) {
        self.alignment = alignment
        self.text = text
        self.font = font
        self.color = color
        self.speed = speed
        self.animates = animates
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scrolls = animates && state.textWidth > width + 0.5

            Group {
                if scrolls, let strip = state.strip(for: stripKey, render: renderStrip) {
                    MarqueeLayer(strip: strip, distance: state.textWidth + Self.gap, speed: speed)
                } else {
                    label
                        .truncationMode(.tail)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: alignment)
            .clipped()
        }
        .background(measurement)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
    }

    /// What the drawn strip depends on.
    private var stripKey: String { "\(text)|\(font.hashValue)|\(color.hashValue)" }

    /// The text and its repeat, side by side, as one image.
    @MainActor
    private func renderStrip() -> MarqueeStrip? {
        let renderer = ImageRenderer(content:
            HStack(spacing: Self.gap) {
                label
                label
            }
            .fixedSize()
            .environment(\.colorScheme, .dark)
        )
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return MarqueeStrip(
            image: image,
            size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
            scale: scale
        )
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
}

/// The text and its repeat drawn once, ready to slide.
struct MarqueeStrip: Equatable {
    let image: CGImage
    let size: CGSize
    let scale: CGFloat

    static func == (lhs: MarqueeStrip, rhs: MarqueeStrip) -> Bool {
        lhs.image === rhs.image
    }
}

private struct MarqueeLayer: NSViewRepresentable {
    let strip: MarqueeStrip
    let distance: CGFloat
    let speed: Double

    func makeNSView(context: Context) -> MarqueeLayerView {
        MarqueeLayerView()
    }

    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        view.update(strip: strip, distance: distance, speed: speed)
    }
}

/// Holds the strip in a layer and slides it with one repeating animation:
/// rest, glide one repeat to the left, jump back unseen (the repeat sits
/// where the text started), again. The leading edge fades only while it
/// moves, switched by a second animation on the same clock.
final class MarqueeLayerView: NSView {
    private let strip = CALayer()
    private let fade = CAGradientLayer()
    private var configured: (image: CGImage, distance: CGFloat, speed: Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        strip.anchorPoint = .zero
        strip.contentsGravity = .resize
        layer?.addSublayer(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(strip new: MarqueeStrip, distance: CGFloat, speed: Double) {
        if let configured, configured.image === new.image, configured.distance == distance, configured.speed == speed {
            return
        }
        configured = (new.image, distance, speed)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.contents = new.image
        strip.contentsScale = new.scale
        strip.bounds = CGRect(origin: .zero, size: new.size)
        CATransaction.commit()
        needsLayout = true
        layoutSubtreeIfNeeded()
        startScrolling(distance: distance, speed: speed)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = strip.bounds.height
        strip.position = CGPoint(x: 0, y: ((bounds.height - height) / 2).rounded())
        fade.frame = bounds
        let edge = min(0.3, MarqueeText.fadeWidth / max(bounds.width, 1))
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        if fade.colors == nil { fade.colors = Self.restingColors }
        CATransaction.commit()
    }

    private static let opaque = NSColor.black.cgColor
    private static let clear = NSColor.clear.cgColor
    /// At rest the text starts right at the leading edge, unfaded.
    private static let restingColors: [CGColor] = [opaque, opaque, opaque, clear]
    private static let movingColors: [CGColor] = [clear, opaque, opaque, clear]

    private func startScrolling(distance: CGFloat, speed: Double) {
        strip.removeAllAnimations()
        fade.removeAllAnimations()
        let rest = MarqueeText.restDuration
        let cycle = rest + Double(distance) / max(speed, 1)
        let restEnd = NSNumber(value: rest / cycle)
        let now = CACurrentMediaTime()

        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0, 0, -distance]
        slide.keyTimes = [0, restEnd, 1]
        slide.duration = cycle
        slide.repeatCount = .infinity
        slide.beginTime = now
        slide.isRemovedOnCompletion = false
        // Small text gliding slowly: 30 frames a second looks the same as
        // 120 and costs the window server a quarter as much.
        if #available(macOS 12, *) {
            slide.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        }
        strip.add(slide, forKey: "marquee")

        let edges = CAKeyframeAnimation(keyPath: "colors")
        edges.values = [Self.restingColors, Self.movingColors]
        edges.keyTimes = [0, restEnd, 1]
        edges.calculationMode = .discrete
        edges.duration = cycle
        edges.repeatCount = .infinity
        edges.beginTime = now
        edges.isRemovedOnCompletion = false
        fade.add(edges, forKey: "edges")
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
    /// The last strip drawn, and what it was drawn from. Not published: it's
    /// derived from the text, and drawing it shouldn't trigger a redraw.
    private var cachedKey: String?
    private var cachedStrip: MarqueeStrip?

    @MainActor
    func strip(for key: String, render: () -> MarqueeStrip?) -> MarqueeStrip? {
        if key == cachedKey, let cachedStrip { return cachedStrip }
        cachedKey = key
        cachedStrip = render()
        return cachedStrip
    }
}
