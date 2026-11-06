import SwiftUI

/// One card listing everything that's running, for when there isn't room to
/// show it all beside the notch (see `ActivityManager.allocate`). Each row
/// says what it is and, where there is one, offers its button.
struct ActivityTrayView: View {
    @ObservedObject var activities: ActivityManager
    @EnvironmentObject private var downloads: DownloadsMonitor

    static let rowHeight: CGFloat = 40
    static let maxRows = 5

    static func size(rows: Int) -> CGSize {
        let shown = CGFloat(min(max(1, rows), maxRows))
        // Room under the rows: the notch's glass fades in along the bottom.
        return CGSize(width: 330, height: 74 + shown * rowHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(activities.trayEntries.prefix(Self.maxRows)) { activity in
                row(activity)
                    .frame(height: Self.rowHeight)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func row(_ activity: LiveActivity) -> some View {
        HStack(spacing: 12) {
            glyph(for: activity)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(for: activity))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle(for: activity)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            action(for: activity)
        }
    }

    // MARK: - What each row says

    @ViewBuilder
    private func glyph(for activity: LiveActivity) -> some View {
        switch activity.kind {
        case .charging:
            Image(systemName: "bolt.fill").foregroundColor(Theme.Status.charging)
        case .privacy:
            Image(systemName: activity.micInUse ? "mic.fill" : "video.fill")
                .foregroundColor(activity.micInUse ? Theme.Status.warning : Theme.Status.charging)
        case .timer:
            Image(systemName: activity.timer?.sleeps == true ? "moon.zzz.fill" : "timer")
                .foregroundColor(Theme.Text.primary)
        case .download:
            Image(systemName: "arrow.down.circle").foregroundColor(Theme.Text.primary)
        case .agent:
            AgentGlyph(state: activity.agent?.state ?? .working, size: 15)
        case .stayAwake:
            Image(systemName: "cup.and.saucer.fill").foregroundColor(Theme.Text.primary)
        case .music, .overflow:
            EmptyView()
        }
    }

    private func title(for activity: LiveActivity) -> String {
        switch activity.kind {
        case .charging: return "Charging"
        case .privacy:
            switch (activity.cameraInUse, activity.micInUse) {
            case (true, true): return "Camera and microphone"
            case (true, false): return "Camera"
            default: return "Microphone"
            }
        case .timer: return activity.timer?.sleeps == true ? "Sleep timer" : "Timer"
        case .download: return downloads.summary?.name ?? "Download"
        case .agent: return activity.agent?.lead?.project ?? "Agent"
        case .stayAwake: return "Staying awake"
        case .music, .overflow: return ""
        }
    }

    @ViewBuilder
    private func subtitle(for activity: LiveActivity) -> some View {
        switch activity.kind {
        case .charging:
            Text("\(activity.level ?? 0)%")
        case .privacy:
            Text("In use")
        case .timer:
            if let session = activity.timer {
                Text(timerInterval: session.start...session.end, countsDown: true, showsHours: false)
            }
        case .download:
            if let fraction = downloads.summary?.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
            } else {
                Text("Downloading")
            }
        case .agent:
            switch activity.agent?.state ?? .working {
            case .working: Text("Working")
            case .needsInput: Text("Needs you")
            case .done: Text("Done")
            }
        case .stayAwake:
            Text("Won't sleep on its own")
        case .music, .overflow:
            EmptyView()
        }
    }

    @ViewBuilder
    private func action(for activity: LiveActivity) -> some View {
        switch activity.kind {
        case .timer:
            button("Cancel") { activities.cancelTimer() }
        case .stayAwake:
            button("Turn Off") { activities.turnOffStayAwake() }
        default:
            EmptyView()
        }
    }

    private func button(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.primary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}
