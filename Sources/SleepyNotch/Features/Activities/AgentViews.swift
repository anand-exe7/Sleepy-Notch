import SwiftUI

/// One glyph per agent state: still, and in colour only where the colour
/// is the message (orange needs you, green is done).
struct AgentGlyph: View {
    let state: AgentState
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .accessibilityLabel(AgentGlyph.label(for: state))
    }

    private var symbol: String {
        switch state {
        case .working: return "sparkles"
        case .needsInput: return "exclamationmark.bubble.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
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

/// Beside the notch when the agent is the main activity and more than one
/// session is running: how many.
struct AgentWingText: View {
    @EnvironmentObject private var agents: AgentStatusService

    var body: some View {
        if let count = agents.summary?.sessions.count, count > 1 {
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(Theme.Text.primary)
        }
    }
}

/// Opened from its bubble: each session and what it's doing.
struct AgentDetail: View {
    @EnvironmentObject private var agents: AgentStatusService

    static let rowHeight: CGFloat = 34
    static let maxRows = 3

    static func size(sessions: Int) -> CGSize {
        let rows = CGFloat(min(max(1, sessions), maxRows))
        return CGSize(width: 292, height: 30 + rows * rowHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((agents.summary?.sessions ?? []).prefix(Self.maxRows))) { session in
                HStack(spacing: 10) {
                    AgentGlyph(state: session.state, size: 16)
                        .frame(width: 22)
                    Text(session.project)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Self.word(session.state))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Text.secondary)
                }
                .frame(height: Self.rowHeight)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    private static func word(_ state: AgentState) -> String {
        switch state {
        case .working: return "Working"
        case .needsInput: return "Needs you"
        case .done: return "Done"
        }
    }
}

/// An agent needs input or has finished: a short row under the notch.
struct AgentNoticeView: View {
    let notice: AgentNotice

    static let contentHeight: CGFloat = 46

    var body: some View {
        HStack(spacing: 8) {
            AgentGlyph(state: notice.state, size: 15)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AgentGlyph.label(for: notice.state)), \(notice.project)")
    }

    private var title: String {
        notice.state == .needsInput
            ? "\(notice.project) needs you"
            : "\(notice.project) finished"
    }
}
