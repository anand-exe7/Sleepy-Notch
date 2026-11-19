import SwiftUI
import AppKit

/// The coding agent's mark, animated by its state: Claude's coral
/// starburst, Gemini's four-point star, Codex's knot, Cursor's cube, a
/// sparkle for anything else.
///
/// The mark never turns:
/// - working: Claude's rays ripple, a wave running round them (Codex's
///   links light in turn; other marks breathe), so it reads "busy";
/// - needs you: the whole mark flares out now and then, with an orange
///   badge;
/// - done: its pieces draw in one by one, then it's still, with a green
///   check (grey stop square when stopped).
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
    /// The mark in pieces, so each can move on its own: Claude's twelve
    /// rays and its centre, Codex's six links, or one piece for the rest.
    private var parts: [CAShapeLayer] = []
    private let holder = CALayer()
    private let gradient = CAGradientLayer()
    private var kind: AgentKind?
    private var state: AgentState?
    private var builtFor: (AgentKind, CGSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(holder)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(kind: AgentKind, state: AgentState) {
        let changed = kind != self.kind || state != self.state
        self.kind = kind
        self.state = state
        needsLayout = true
        if changed { animate() }
    }

    override func layout() {
        super.layout()
        guard let kind, bounds.width > 0 else { return }
        if let built = builtFor, built.0 == kind, built.1 == bounds.size { return }
        builtFor = (kind, bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = bounds
        parts.forEach { $0.removeFromSuperlayer() }
        gradient.removeFromSuperlayer()
        parts = Self.pieces(for: kind, in: bounds).map { path in
            let piece = CAShapeLayer()
            piece.frame = bounds
            piece.path = path
            piece.lineJoin = .round
            piece.lineCap = .round
            switch kind {
            case .claude:
                piece.fillColor = AgentMarkLayerView.tint(.claude).cgColor
            case .codex, .cursor:
                piece.fillColor = nil
                piece.strokeColor = NSColor.white.cgColor
                piece.lineWidth = max(1.2, bounds.width * 0.085)
            case .gemini, .other:
                piece.fillColor = NSColor.white.cgColor
            }
            return piece
        }
        if kind == .gemini, let star = parts.first {
            // The star as a mask over a gradient: blue into violet into rose.
            gradient.frame = bounds
            gradient.colors = [
                NSColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 1).cgColor,
                NSColor(red: 0.72, green: 0.56, blue: 0.95, alpha: 1).cgColor,
                NSColor(red: 0.98, green: 0.52, blue: 0.56, alpha: 1).cgColor,
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            gradient.mask = star
            holder.addSublayer(gradient)
        } else {
            parts.forEach { holder.addSublayer($0) }
        }
        CATransaction.commit()
        animate()
    }

    // MARK: - Motion

    private func animate() {
        holder.removeAllAnimations()
        gradient.removeAllAnimations()
        parts.forEach { $0.removeAllAnimations() }
        guard let state, let kind, !parts.isEmpty else { return }
        let now = CACurrentMediaTime()
        switch state {
        case .working:
            switch kind {
            case .claude:
                // A wave runs round the rays: each grows out a little and
                // settles, one after the next. The centre holds still.
                let rays = parts.dropLast()
                let cycle = 1.8
                for (index, ray) in rays.enumerated() {
                    let grow = CAKeyframeAnimation(keyPath: "transform.scale")
                    grow.values = [1, 1.3, 1, 1]
                    grow.keyTimes = [0, 0.14, 0.32, 1]
                    grow.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
                    grow.duration = cycle
                    grow.repeatCount = .infinity
                    grow.beginTime = now + cycle * Double(index) / Double(rays.count)
                    grow.fillMode = .backwards
                    limit(grow)
                    ray.add(grow, forKey: "ripple")
                }
            case .codex:
                // The links light up in turn.
                let cycle = 1.6
                for (index, link) in parts.enumerated() {
                    let light = CAKeyframeAnimation(keyPath: "opacity")
                    light.values = [0.35, 1, 0.35, 0.35]
                    light.keyTimes = [0, 0.15, 0.4, 1]
                    light.duration = cycle
                    light.repeatCount = .infinity
                    light.beginTime = now + cycle * Double(index) / Double(parts.count)
                    light.fillMode = .backwards
                    limit(light)
                    link.add(light, forKey: "light")
                }
            case .gemini, .cursor, .other:
                let breathe = CABasicAnimation(keyPath: "transform.scale")
                breathe.fromValue = 0.84
                breathe.toValue = 1.0
                breathe.duration = 1.1
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                limit(breathe)
                holder.add(breathe, forKey: "breathe")
            }
        case .needsInput:
            // Everything flares out together, then holds; again after a pause.
            let flare = CAKeyframeAnimation(keyPath: "transform.scale")
            flare.values = [1, 1.22, 0.96, 1, 1]
            flare.keyTimes = [0, 0.1, 0.2, 0.28, 1]
            flare.duration = 2.4
            flare.repeatCount = .infinity
            limit(flare)
            holder.add(flare, forKey: "flare")
        case .done:
            // The pieces draw in one by one, then it's still.
            for (index, piece) in parts.enumerated() {
                let appear = CABasicAnimation(keyPath: "opacity")
                appear.fromValue = 0
                appear.toValue = 1
                appear.duration = 0.18
                appear.beginTime = now + 0.035 * Double(index)
                appear.fillMode = .backwards
                piece.add(appear, forKey: "appear")
            }
        }
    }

    /// The loops don't need the display's full rate.
    private func limit(_ animation: CAAnimation) {
        if #available(macOS 14, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }
    }

    /// The agent's own colour.
    static func tint(_ kind: AgentKind) -> NSColor {
        switch kind {
        case .claude: return NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)
        case .gemini: return NSColor(red: 0.45, green: 0.6, blue: 1.0, alpha: 1)
        case .codex, .cursor, .other: return .white
        }
    }

    // MARK: - Marks

    /// The mark as separately movable pieces.
    static func pieces(for kind: AgentKind, in rect: CGRect) -> [CGPath] {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = side / 2
        switch kind {
        case .claude:
            // An irregular starburst of rounded rays, like Claude's mark,
            // then its centre.
            let lengths: [CGFloat] = [1.0, 0.78, 0.94, 0.72, 0.98, 0.82, 0.9, 0.74, 1.0, 0.8, 0.92, 0.76]
            var paths: [CGPath] = lengths.enumerated().map { index, length in
                let angle = CGFloat(index) / CGFloat(lengths.count) * 2 * .pi + 0.08 * CGFloat(index % 3)
                let width = r * 0.2
                let ray = CGRect(x: -width / 2, y: r * 0.06, width: width, height: r * length * 0.8)
                var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                return CGPath(roundedRect: ray, cornerWidth: width / 2, cornerHeight: width / 2, transform: &transform)
            }
            paths.append(CGPath(ellipseIn: CGRect(x: center.x - r * 0.2, y: center.y - r * 0.2, width: r * 0.4, height: r * 0.4), transform: nil))
            return paths
        case .codex:
            return (0..<6).map { index in
                let angle = CGFloat(index) * .pi / 3
                let link = CGRect(x: -r * 0.2, y: -r * 0.86, width: r * 0.4, height: r * 0.86)
                var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
                return CGPath(roundedRect: link, cornerWidth: r * 0.2, cornerHeight: r * 0.2, transform: &transform)
            }
        case .gemini, .other:
            let path = CGMutablePath()
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
            return [path]
        case .cursor:
            let path = CGMutablePath()
            let points = (0..<6).map { index -> CGPoint in
                let angle = CGFloat(index) * .pi / 3 - .pi / 2
                return CGPoint(x: center.x + r * 0.9 * cos(angle), y: center.y + r * 0.9 * sin(angle))
            }
            path.addLines(between: points + [points[0]])
            path.move(to: center); path.addLine(to: points[0])
            path.move(to: center); path.addLine(to: points[2])
            path.move(to: center); path.addLine(to: points[4])
            return [path]
        }
    }
}
