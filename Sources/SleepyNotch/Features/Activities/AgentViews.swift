import SwiftUI

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

/// Opened from its bubble: each session as a small card: its animated
/// logo, the project and agent, what it's doing this second (from its
/// transcript), the task you gave it, and where it stands.
struct AgentDetail: View {
    @EnvironmentObject private var agents: AgentStatusService

    static let rowHeight: CGFloat = 72
    static let maxRows = 3
    static let width: CGFloat = 410

    static func size(sessions: Int) -> CGSize {
        let rows = CGFloat(min(max(1, sessions), maxRows))
        return CGSize(width: width, height: 22 + rows * rowHeight + (rows - 1) * 6)
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array((agents.summary?.sessions ?? []).prefix(Self.maxRows))) { session in
                row(session)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: agents.summary)
    }

    private func row(_ session: AgentSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AgentBadge(kind: session.kind, state: session.state, stopped: session.stopped, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                    Text(session.kind.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
                statusLine(session)
                if let task = session.task, session.state != .done {
                    Text("\u{201C}\(task)\u{201D}")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 6)
            chip(session)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(session.state == .needsInput ? 0.075 : 0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            session.state == .needsInput ? Theme.Status.warning.opacity(0.35) : Color.white.opacity(0.05),
                            lineWidth: session.state == .needsInput ? 1 : 0.5
                        )
                )
        )
        .accessibilityElement(children: .combine)
    }

    /// What it's doing now, why it waits, or how it ended, with an icon.
    private func statusLine(_ session: AgentSession) -> some View {
        let (symbol, text, color): (String, String, Color) = {
            switch session.state {
            case .working:
                return (session.action?.symbol ?? "ellipsis", session.action?.text ?? "Starting…", Theme.Text.secondary)
            case .needsInput:
                return ("hand.raised.fill", session.request ?? "Waiting for you", Theme.Status.warning)
            case .done:
                return (session.stopped ? "stop.circle" : "checkmark.circle", session.subtitle, Theme.Text.secondary)
            }
        }()
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .contentTransition(.opacity)
        }
        .foregroundColor(color)
        .animation(.easeOut(duration: 0.2), value: text)
    }

    @ViewBuilder
    private func chip(_ session: AgentSession) -> some View {
        switch session.state {
        case .working:
            Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.Text.primary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .fixedSize()
        case .needsInput:
            label("Needs you", color: Theme.Status.warning)
        case .done:
            if session.stopped {
                label("Stopped", color: Color(white: 0.7))
            } else {
                label("Done", color: Theme.Status.charging)
            }
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(color.opacity(0.16)))
            .fixedSize()
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
