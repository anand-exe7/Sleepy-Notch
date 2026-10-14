import SwiftUI

/// "Standup in 5 min", with a Join button when the event has a video link.
/// The peek stays while the pointer is on it, so the button can be reached
/// (see `PeekContent.isInteractive`).
struct MeetingPeekView: View {
    let meeting: MeetingReminder
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: meeting.calendarColor))
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(meeting.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(countdown)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Text.secondary)
                        .fixedSize()
                }
                Text(timeRange)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let url = meeting.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Join")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Join \(meeting.title)")
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Text.tertiary)
            }
        }
        .padding(.horizontal, 18)
    }

    private var countdown: String {
        let minutes = Int((meeting.start.timeIntervalSinceNow / 60).rounded(.up))
        return minutes <= 0 ? "now" : "in \(minutes) min"
    }

    private var timeRange: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: meeting.start, to: meeting.end)
    }
}
