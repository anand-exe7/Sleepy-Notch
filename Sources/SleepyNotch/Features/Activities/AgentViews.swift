import SwiftUI
import AppKit

/// The agent's mark wherever a small sign of it is needed (the bubble, the
/// wings, the tray, the pill): its logo, animated by its state (see
/// `AgentLogo`). The state's symbol, colour and label stay available for
/// places that want them.
struct AgentGlyph: View {
    let state: AgentState
    var size: CGFloat = 12
    @EnvironmentObject private var agents: AgentStatusService

    var body: some View {
        let lead = agents.summary?.lead
        AgentLogo(kind: lead?.kind ?? .claude, state: state, stopped: lead?.stopped ?? false, size: size * 1.6, showsBadge: state != .working)
    }

    static func symbol(_ state: AgentState) -> String {
        switch state {
        case .working: return "sparkles"
        case .needsInput: return "hand.raised.fill"
        case .done: return "checkmark"
        }
    }

    static func color(_ state: AgentState) -> Color {
        switch state {
        case .working: return Theme.Text.primary
        case .needsInput: return Theme.Status.warning
        case .done: return Theme.Status.charging
        }
    }

    static func label(for state: AgentState) -> String {
        switch state {
        case .working: return "Agent working"
        case .needsInput: return "Agent needs input"
        case .done: return "Agent finished"
        }
    }
}

/// The logo on a soft disc tinted by the state, for rows and notices.
struct AgentBadge: View {
    let kind: AgentKind
    let state: AgentState
    var stopped = false
    var size: CGFloat = 30

    var body: some View {
        AgentLogo(kind: kind, state: state, stopped: stopped, size: size * 0.66)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(state == .working ? 0.07 : 0.16)))
            .overlay(Circle().strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
    }

    private var tint: Color {
        if state == .done && stopped { return Color(white: 0.6) }
        return state == .working ? .white : AgentGlyph.color(state)
    }
}

/// Beside the notch when the agent is the main activity: the turn's running
/// clock while it works (drawn by the system, nothing ticks here), "Needs
/// you" when it's waiting, how long it took when it's done; "×2" when more
/// than one session runs.
struct AgentWingText: View {
    @EnvironmentObject private var agents: AgentStatusService

    var body: some View {
        if let summary = agents.summary, let lead = summary.lead {
            HStack(spacing: 4) {
                switch lead.state {
                case .working:
                    Text(timerInterval: lead.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.primary)
                case .needsInput:
                    Text("Needs you")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Theme.Status.warning)
                case .done:
                    Text(lead.duration.map(AgentSession.format) ?? "Done")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.Status.charging)
                }
                if summary.sessions.count > 1 {
                    Text("×\(summary.sessions.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}

/// Opened from its bubble. The session that leads gets the full card: its
/// animated logo, the project with the agent's name as a coloured capsule,
/// your prompt, a short timeline of its last steps (the running one marked
/// by a pulsing dot), and a tally of what it has done. Other sessions sit
/// under it as compact rows.
struct AgentDetail: View {
    @EnvironmentObject private var agents: AgentStatusService

    static let width: CGFloat = 420
    static let leadHeight: CGFloat = 156
    static let rowHeight: CGFloat = 56
    static let maxRows = 3

    static func size(sessions: Int) -> CGSize {
        let others = CGFloat(min(max(1, sessions), maxRows) - 1)
        return CGSize(width: width, height: 20 + leadHeight + others * (rowHeight + 6))
    }

    var body: some View {
        let sessions = Array((agents.summary?.sessions ?? []).prefix(Self.maxRows))
        let lead = agents.summary?.lead ?? sessions.first
        VStack(spacing: 6) {
            if let lead {
                AgentSessionCard(session: lead)
                    .frame(height: Self.leadHeight)
            }
            ForEach(sessions.filter { $0.id != lead?.id }) { session in
                AgentSessionRow(session: session)
                    .frame(height: Self.rowHeight)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: agents.summary)
    }
}

/// The type used across the agent views.
private enum AgentType {
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func timer(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
}

/// The lead session, in full.
private struct AgentSessionCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AgentBadge(kind: session.kind, state: session.state, stopped: session.stopped, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 7) {
                        Text(session.project)
                            .font(AgentType.title(16))
                            .foregroundColor(Theme.Text.primary)
                            .lineLimit(1)
                        AgentNameChip(kind: session.kind)
                    }
                    if let task = session.task {
                        Text(task)
                            .font(.system(size: 11.5, weight: .regular).italic())
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                AgentStateChip(session: session)
            }
            AgentTimeline(session: session)
                .padding(.leading, 56)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
        .background(AgentCardBackground(kind: session.kind, state: session.state))
        .accessibilityElement(children: .combine)
    }
}

/// Another session: logo, name, what it's on, where it stands.
private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 11) {
            AgentBadge(kind: session.kind, state: session.state, stopped: session.stopped, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(AgentType.title(13.5))
                        .foregroundColor(Theme.Text.primary)
                    AgentNameChip(kind: session.kind, compact: true)
                }
                Text(session.state == .working ? (session.toolRunning ? session.action?.running : session.action?.text) ?? "Thinking" : session.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(session.state == .needsInput ? Theme.Status.warning : Theme.Text.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            AgentStateChip(session: session)
        }
        .padding(.horizontal, 12)
        .background(AgentCardBackground(kind: session.kind, state: session.state))
        .accessibilityElement(children: .combine)
    }
}

/// The last few steps, oldest first, and a tally under them.
private struct AgentTimeline: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 7) {
                    marker(row.mark)
                        .frame(width: 12, height: 12)
                    Image(systemName: row.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(row.mark == .done ? Theme.Text.tertiary : row.color)
                        .frame(width: 12)
                    Text(row.text)
                        .font(.system(size: 12, weight: row.mark == .done ? .regular : .medium))
                        .foregroundColor(row.mark == .done ? Theme.Text.tertiary : row.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            if let stats = session.stats {
                Text(stats)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundColor(Theme.Text.tertiary.opacity(0.8))
                    .padding(.top, 2)
                    .padding(.leading, 38)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: rows.map(\.text))
    }

    enum Mark { case done, now, warning, finished, stopped }

    struct Row {
        let mark: Mark
        let symbol: String
        let text: String
        let color: Color
    }

    /// Finished steps, then where it is now.
    private var rows: [Row] {
        let steps = session.steps
        let runningLast = session.state == .working && session.toolRunning && !steps.isEmpty
        var rows: [Row] = steps.enumerated().map { index, step in
            let running = runningLast && index == steps.count - 1
            return Row(mark: running ? .now : .done, symbol: step.symbol, text: running ? step.running : step.text, color: Theme.Text.primary)
        }
        switch session.state {
        case .working where !runningLast:
            let thinking = session.action.flatMap { $0.isTool ? nil : $0 }
            rows.append(Row(mark: .now, symbol: thinking?.symbol ?? "brain", text: (thinking?.text ?? "Thinking") + "…", color: Theme.Text.primary))
        case .needsInput:
            rows.append(Row(mark: .warning, symbol: "hand.raised.fill", text: session.request ?? "Waiting for you", color: Theme.Status.warning))
        case .done:
            // The prompt is already shown above: just how it ended.
            let took = session.duration.map(AgentSession.format)
            let text = session.stopped
                ? took.map { "Stopped after \($0)" } ?? "Stopped"
                : took.map { "Finished in \($0)" } ?? "Finished"
            rows.append(Row(mark: session.stopped ? .stopped : .finished, symbol: session.stopped ? "stop.fill" : "checkmark", text: text, color: session.stopped ? Color(white: 0.7) : Theme.Status.charging))
        default:
            break
        }
        return Array(rows.suffix(3))
    }

    @ViewBuilder
    private func marker(_ mark: Mark) -> some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.Text.tertiary.opacity(0.7))
        case .now:
            PulsingDot(color: AgentMarkLayerView.tint(session.kind))
        case .warning:
            PulsingDot(color: NSColor.systemOrange)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.Status.charging)
        case .stopped:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.6))
        }
    }
}

/// The agent's name as a small capsule in its colour.
private struct AgentNameChip: View {
    let kind: AgentKind
    var compact = false

    var body: some View {
        let tint = Color(nsColor: AgentMarkLayerView.tint(kind))
        Text(kind.name)
            .font(.system(size: compact ? 9.5 : 10, weight: .semibold))
            .foregroundColor(kind == .codex || kind == .cursor || kind == .other ? Theme.Text.secondary : tint)
            .padding(.horizontal, 7)
            .frame(height: compact ? 16 : 18)
            .background(Capsule().fill(tint.opacity(0.14)))
            .fixedSize()
    }
}

/// The clock while it works; "Needs you", "Done" or "Stopped" otherwise.
private struct AgentStateChip: View {
    let session: AgentSession

    var body: some View {
        switch session.state {
        case .working:
            Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                .font(AgentType.timer(12.5))
                .foregroundColor(Theme.Text.primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .fixedSize()
        case .needsInput:
            label("Needs you", color: Theme.Status.warning)
        case .done:
            if session.stopped {
                label("Stopped", color: Color(white: 0.72))
            } else {
                label(session.duration.map(AgentSession.format) ?? "Done", color: Theme.Status.charging)
            }
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AgentType.timer(11.5))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(color.opacity(0.16)))
            .fixedSize()
    }
}

/// A soft plate, faintly tinted in the agent's colour from the left, with
/// an orange edge while it needs you.
private struct AgentCardBackground: View {
    let kind: AgentKind
    let state: AgentState

    var body: some View {
        let tint = Color(nsColor: AgentMarkLayerView.tint(kind))
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.1), tint.opacity(0)], startPoint: .leading, endPoint: .center))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        state == .needsInput ? Theme.Status.warning.opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: state == .needsInput ? 1 : 0.5
                    )
            )
    }
}

/// A small dot that pulses, for the step running now. A Core Animation
/// loop in the window server; nothing redraws here.
private struct PulsingDot: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> PulsingDotView { PulsingDotView() }
    func updateNSView(_ view: PulsingDotView, context: Context) { view.color = color }
}

private final class PulsingDotView: NSView {
    private let dot = CALayer()
    private let halo = CALayer()
    var color: NSColor = .white {
        didSet {
            dot.backgroundColor = color.cgColor
            halo.backgroundColor = color.withAlphaComponent(0.35).cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(halo)
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let small = side * 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = CGRect(x: bounds.midX - small / 2, y: bounds.midY - small / 2, width: small, height: small)
        dot.cornerRadius = small / 2
        halo.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        halo.cornerRadius = side / 2
        CATransaction.commit()
        guard halo.animation(forKey: "pulse") == nil else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.4
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [grow, fade]
        pulse.duration = 1.3
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if #available(macOS 14, *) {
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }
        halo.add(pulse, forKey: "pulse")
    }
}

/// An agent started, needs input or has finished: a row under the notch,
/// with a second line saying what it's on, why it needs you or how long it
/// took.
struct AgentNoticeView: View {
    let notice: AgentNotice

    static let contentHeight: CGFloat = 46
    static func height(for notice: AgentNotice) -> CGFloat {
        (notice.detail?.count ?? 0) > 2 ? 62 : 52
    }

    var body: some View {
        HStack(spacing: 10) {
            // The playful line carries its own emoji.
            AgentBadge(kind: notice.kind, state: notice.state, stopped: notice.stopped, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .minimumScaleFactor(0.85)
                // A prompt of a letter or two ("x", "ok") says nothing.
                if let detail = notice.detail, detail.count > 2 {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        // The logo and its lines as one group in the middle of the peek
        // (left-aligned, they hugged the left and left the right half
        // empty).
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AgentGlyph.label(for: notice.state)), \(notice.project)")
    }

    private var title: String {
        if let message = notice.message { return message }
        switch notice.state {
        case .needsInput: return "\(notice.project) needs you"
        case .done: return notice.stopped ? "\(notice.project) stopped" : "\(notice.project) finished"
        case .working: return "\(notice.project) is working"
        }
    }
}
