import SwiftUI

/// "Standup in 5 min": a countdown ring in the calendar's colour with the
/// minutes inside it, the title and time, and a Join button when the event
/// has a video link. The peek stays while the pointer is on it, so the
/// button can be reached (see `PeekContent.isInteractive`).
struct MeetingPeekView: View {
    let meeting: MeetingReminder
    let dismiss: () -> Void
    /// Draws the settled state straight away, for previews.
    var startSettled = false

    @StateObject private var reveal = MeetingReveal()

    private var color: Color { Color(nsColor: meeting.calendarColor) }

    private var minutesLeft: Int {
        max(0, Int((meeting.start.timeIntervalSinceNow / 60).rounded(.up)))
    }

    var body: some View {
        HStack(spacing: 12) {
            countdown

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(details)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(reveal.isShown ? 1 : 0)
            .offset(x: reveal.isShown ? 0 : -6)

            Spacer(minLength: 8)

            if let url = meeting.joinURL {
                joinButton(url)
                    .opacity(reveal.isShown ? 1 : 0)
                    .scaleEffect(reveal.isShown ? 1 : 0.8)
            }
        }
        .padding(.horizontal, 18)
        .onAppear {
            if startSettled { reveal.isShown = true } else { reveal.run() }
        }
    }

    // MARK: - Countdown

    /// The ring is full five minutes out and runs down to the start.
    private var countdown: some View {
        let fraction = min(1, max(0.04, meeting.start.timeIntervalSinceNow / CalendarMonitor.leadTime))
        return ZStack {
            Circle()
                .fill(color.opacity(0.16))
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 3)
                .padding(1.5)
            Circle()
                .trim(from: 0, to: reveal.isShown ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
            VStack(spacing: -2) {
                if minutesLeft > 0 {
                    Text("\(minutesLeft)")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                    Text("min")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.Text.secondary)
                } else {
                    Text("Now")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundColor(Theme.Text.primary)
        }
        .frame(width: 42, height: 42)
        .scaleEffect(reveal.isShown ? 1 : 0.7)
    }

    // MARK: - Details

    private var details: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: meeting.start, to: meeting.end)
        guard let service = serviceName else { return time }
        return "\(time) · \(service)"
    }

    private var serviceName: String? {
        guard let host = meeting.joinURL?.host?.lowercased() else { return nil }
        let names: [(String, String)] = [
            ("zoom.us", "Zoom"), ("meet.google.com", "Google Meet"),
            ("teams.microsoft.com", "Teams"), ("teams.live.com", "Teams"),
            ("webex.com", "Webex"), ("facetime.apple.com", "FaceTime"),
            ("whereby.com", "Whereby"), ("meet.jit.si", "Jitsi"), ("chime.aws", "Chime"),
        ]
        return names.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1
    }

    private func joinButton(_ url: URL) -> some View {
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
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Join \(meeting.title)")
    }
}

/// See `NotchInteractionState` for why this isn't `@State`.
private final class MeetingReveal: ObservableObject {
    @Published var isShown = false

    func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                self.isShown = true
            }
        }
    }
}
