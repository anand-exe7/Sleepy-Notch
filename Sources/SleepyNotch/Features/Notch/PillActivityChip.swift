import SwiftUI

/// On a Mac with no notch the island is a pill with no wings or bubbles, so
/// the live activities that have no place of their own in it (the screen
/// recording, a timer, a download, the coding agent, Stay Awake) share one
/// chip: the most important of them, and "+N" when more are running. The
/// camera and mic, and the charge, already have their own spots in the pill.
struct PillActivityChip: View {
    @ObservedObject var activities: ActivityManager

    /// The kinds this chip speaks for, most important first.
    private static let kinds: [ActivityKind] = [.recording, .timer, .download, .agent, .stayAwake]

    private var running: [LiveActivity] {
        activities.activities
            .filter { Self.kinds.contains($0.kind) }
            .sorted { $0.priority < $1.priority }
    }

    var body: some View {
        if let first = running.first {
            HStack(spacing: 4) {
                content(for: first)
                if running.count > 1 {
                    Text("+\(running.count - 1)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func content(for activity: LiveActivity) -> some View {
        switch activity.kind {
        case .recording:
            RecordingDot(size: 8)
            if let since = activity.recordingSince { RecordingWingText(since: since) }
        case .timer:
            Image(systemName: activity.timer?.symbol ?? "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            if let session = activity.timer { TimerWingText(session: session) }
        case .download:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            DownloadWingText()
        case .agent:
            AgentGlyph(state: activity.agent?.state ?? .working, size: 11)
        case .stayAwake:
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
        default:
            EmptyView()
        }
    }
}
