import SwiftUI
import AppKit

/// The coding agent's mark, animated by its state: Claude's coral
/// starburst, Gemini's four-point star, Codex's knot, Cursor's cube, a
/// sparkle for anything else.
///
/// The mark itself never turns. Around it:
/// - working: a thin arc in the agent's colour circles the mark, and the
///   mark breathes gently, so it reads "busy" at a glance;
/// - needs you: the mark gives a small bounce now and then, with an orange
///   badge;
/// - done: still, with a green check (grey stop square when stopped).
///
/// All motion is Core Animation loops run by the window server (like the
/// equalizer bars), not SwiftUI redraws, capped at 30 fps on macOS 14+;
/// it stops with the view.
struct AgentLogo: View {
    let kind: AgentKind
    let state: AgentState
    var stopped = false
    var size: CGFloat = 16
    /// Small places (the bubble, the wings) leave the badge off: the
    /// motion and colour of the bubble already say it.
    var showsBadge = true

    var body: some View {
        AgentMarkView(kind: kind, state: state)
            .frame(width: size, height: size)
            .opacity(state == .done ? 0.92 : 1)
            .overlay(alignment: .bottomTrailing) {
                if showsBadge, let badge {
                    badge
                        .frame(width: size * 0.46, height: size * 0.46)
                        .offset(x: size * 0.1, y: size * 0.1)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.7), value: state)
            .accessibilityLabel("\(kind.name), \(AgentGlyph.label(for: state).lowercased())")
    }

    private var badge: AnyView? {
        switch state {
        case .working:
            return nil
        case .needsInput:
            return AnyView(Self.badge("exclamationmark", Theme.Status.warning))
        case .done:
            return AnyView(stopped ? Self.badge("stop.fill", Color(white: 0.55)) : Self.badge("checkmark", Theme.Status.charging))
        }
    }

    private static func badge(_ symbol: String, _ color: Color) -> some View {
        GeometryReader { proxy in
            Image(systemName: symbol)
                .font(.system(size: proxy.size.width * 0.55, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Circle().fill(color))
                .overlay(Circle().strokeBorder(Color.black, lineWidth: max(1, proxy.size.width * 0.12)))
        }
    }
}

private struct AgentMarkView: NSViewRepresentable {
    let kind: AgentKind
    let state: AgentState

    func makeNSView(context: Context) -> AgentMarkLayerView { AgentMarkLayerView() }

    func updateNSView(_ view: AgentMarkLayerView, context: Context) {
        view.configure(kind: kind, state: state)
    }
}

final class AgentMarkLayerView: NSView {
    private let spinner = CALayer()
    private let mark = CAShapeLayer()
    /// The arc that circles the mark while the agent works.
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private var kind: AgentKind?
    private var state: AgentState?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        spinner.addSublayer(mark)
        for line in [track, ring] {
            line.fillColor = nil
            line.lineCap = .round
            layer?.addSublayer(line)
        }
        layer?.addSublayer(spinner)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(kind: AgentKind, state: AgentState) {
        let kindChanged = kind != self.kind
        let stateChanged = state != self.state
        self.kind = kind
        self.state = state
        if kindChanged { needsLayout = true }
        if stateChanged || kindChanged { animate() }
    }

    override func layout() {
        super.layout()
        guard let kind else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spinner.frame = bounds
        mark.frame = bounds
        gradient.frame = bounds
        // The ring runs round the edge; the mark sits inside it.
        let lineWidth = max(1.2, bounds.width * 0.075)
        let circle = CGPath(ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        for line in [track, ring] {
            line.frame = bounds
            line.path = circle
            line.lineWidth = lineWidth
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.1).cgColor
        ring.strokeColor = Self.tint(kind).cgColor
        ring.strokeStart = 0
        ring.strokeEnd = 0.3
        let path = Self.path(for: kind, in: bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2))
        mark.path = path
        mark.lineJoin = .round
        mark.lineCap = .round
        gradient.removeFromSuperlayer()
        gradient.mask = nil
        switch kind {
        case .claude:
            mark.fillColor = NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1).cgColor
            mark.strokeColor = nil
        case .gemini:
            // A shape mask over a gradient: blue into violet into rose.
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.path = path
            gradient.colors = [
                NSColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1).cgColor,
                NSColor(red: 0.72, green: 0.56, blue: 0.95, alpha: 1).cgColor,
                NSColor(red: 0.98, green: 0.52, blue: 0.56, alpha: 1).cgColor,
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            gradient.mask = shape
            mark.fillColor = nil
            mark.strokeColor = nil
            spinner.addSublayer(gradient)
        case .codex, .cursor:
            mark.fillColor = nil
            mark.strokeColor = NSColor.white.cgColor
            mark.lineWidth = max(1.2, bounds.width * 0.085)
        case .other:
            mark.fillColor = NSColor.white.cgColor
            mark.strokeColor = nil
        }
        CATransaction.commit()
    }

    // MARK: - Motion

    private func animate() {
        spinner.removeAllAnimations()
        ring.removeAllAnimations()
        guard let state else { return }
        let working = state == .working
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !working
        track.isHidden = !working
        CATransaction.commit()
        switch state {
        case .working:
            // The arc circles; the mark stays put and breathes.
            let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
            orbit.fromValue = 0
            orbit.toValue = -2 * Double.pi
            orbit.duration = 1.4
            orbit.repeatCount = .infinity
            limit(orbit)
            ring.add(orbit, forKey: "orbit")

            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.88
            breathe.toValue = 1.0
            breathe.duration = 1.2
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            limit(breathe)
            spinner.add(breathe, forKey: "breathe")
        case .needsInput:
            // A small bounce, then a pause, over and over: no turning.
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [1, 1.18, 0.94, 1.06, 1, 1]
            bounce.keyTimes = [0, 0.08, 0.16, 0.24, 0.32, 1]
            bounce.duration = 2.2
            bounce.repeatCount = .infinity
            limit(bounce)
            spinner.add(bounce, forKey: "bounce")
        case .done:
            // One settle, then still.
            let settle = CASpringAnimation(keyPath: "transform.scale")
            settle.fromValue = 0.7
            settle.toValue = 1
            settle.damping = 9
            settle.stiffness = 180
            settle.duration = settle.settlingDuration
            spinner.add(settle, forKey: "settle")
        }
    }

    /// The agent's own colour, for the working ring.
    static func tint(_ kind: AgentKind) -> NSColor {
        switch kind {
        case .claude: return NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)
        case .gemini: return NSColor(red: 0.45, green: 0.6, blue: 1.0, alpha: 1)
        case .codex, .cursor, .other: return .white
        }
    }

    /// The loops don't need the display's full rate.
    private func limit(_ animation: CAAnimation) {
        if #available(macOS 14, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }
    }

    // MARK: - Marks

    static func path(for kind: AgentKind, in rect: CGRect) -> CGPath {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = side / 2
        let path = CGMutablePath()
        switch kind {
        case .claude:
            // An irregular starburst of rounded rays, like Claude's mark.
            let lengths: [CGFloat] = [1.0, 0.78, 0.94, 0.72, 0.98, 0.82, 0.9, 0.74, 1.0, 0.8, 0.92, 0.76]
            for (index, length) in lengths.enumerated() {
                let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi + 0.08 * CGFloat(index % 3)
                let width = r * 0.2
                let ray = CGRect(x: -width / 2, y: r * 0.06, width: width, height: r * length * 0.94)
                let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                path.addPath(CGPath(roundedRect: ray, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil), transform: transform)
            }
            path.addEllipse(in: CGRect(x: center.x - r * 0.2, y: center.y - r * 0.2, width: r * 0.4, height: r * 0.4))
        case .gemini, .other:
            // Four points with curved, pinched sides.
            let top = CGPoint(x: center.x, y: center.y - r)
            let right = CGPoint(x: center.x + r, y: center.y)
            let bottom = CGPoint(x: center.x, y: center.y + r)
            let left = CGPoint(x: center.x - r, y: center.y)
            path.move(to: top)
            path.addQuadCurve(to: right, control: center)
            path.addQuadCurve(to: bottom, control: center)
            path.addQuadCurve(to: left, control: center)
            path.addQuadCurve(to: top, control: center)
            path.closeSubpath()
        case .codex:
            // Six rounded links around the middle: a knot.
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3
                let link = CGRect(x: -r * 0.2, y: -r * 0.86, width: r * 0.4, height: r * 0.86)
                let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                path.addPath(CGPath(roundedRect: link, cornerWidth: r * 0.2, cornerHeight: r * 0.2, transform: nil), transform: transform)
            }
        case .cursor:
            // A cube seen corner on.
            let points = (0..<6).map { index -> CGPoint in
                let angle = CGFloat(index) * .pi / 3 - .pi / 2
                return CGPoint(x: center.x + r * 0.9 * cos(angle), y: center.y + r * 0.9 * sin(angle))
            }
            path.addLines(between: points + [points[0]])
            path.move(to: center); path.addLine(to: points[0])
            path.move(to: center); path.addLine(to: points[2])
            path.move(to: center); path.addLine(to: points[4])
        }
        return path
    }
}
