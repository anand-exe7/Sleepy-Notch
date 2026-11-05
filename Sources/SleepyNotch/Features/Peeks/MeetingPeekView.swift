import SwiftUI
import AppKit

/// A meeting about to start, laid out like the other cards: "Starting in
/// 5 min" with the calendar's colour in one line under the notch, and below
/// it a countdown ring with the minutes, the meeting's name and time, and a
/// Join button when the event has a video link.
///
/// The row rises from below on the same fast-then-gentle curve as the other
/// cards, the ring sweeps round to the time left, and the Join button
/// arrives last. The peek stays while the pointer is on it, so the button
/// can be reached (see `PeekContent.isInteractive`).
struct MeetingPeekView: View {
    let meeting: MeetingReminder
    let dismiss: () -> Void
    /// Draws the settled state straight away, for previews.
    var startSettled = false

    @StateObject private var reveal = MeetingReveal()

    /// The height the peek drops below the notch.
    static let contentHeight: CGFloat = 104

    private var color: Color { Color(nsColor: meeting.calendarColor) }

    private var minutesLeft: Int {
        max(0, Int((meeting.start.timeIntervalSinceNow / 60).rounded(.up)))
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .opacity(reveal.text ? 1 : 0)
                .offset(y: reveal.text ? 0 : 4)

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                countdown

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(timeRange)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let url = meeting.joinURL {
                    joinButton(url)
                        .opacity(reveal.join ? 1 : 0)
                        .scaleEffect(reveal.join ? 1 : 0.85)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .offset(y: reveal.risen ? 0 : 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if startSettled { reveal.settle() } else { reveal.run() }
        }
        .onDisappear { reveal.cancel() }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(minutesLeft > 0 ? "Starting in \(minutesLeft) min" : "Starting now")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            if let service = serviceName {
                Text(service)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
        }
        // Lines up with the row below.
        .padding(.horizontal, 22)
    }

    // MARK: - Countdown

    /// The ring is full five minutes out and runs down to the start.
    private var countdown: some View {
        let fraction = min(1, max(0.04, meeting.start.timeIntervalSinceNow / CalendarMonitor.leadTime))
        return ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: reveal.ring ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                if minutesLeft > 0 {
                    Text("\(minutesLeft)")
                        .font(.system(size: 19, weight: .semibold))
                        .monospacedDigit()
                    Text("min")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.Text.secondary)
                } else {
                    Text("Now")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundColor(Theme.Text.primary)
        }
        .padding(1.75)
        .frame(width: 52, height: 52)
    }

    // MARK: - Details

    private var timeRange: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: meeting.start, to: meeting.end)
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
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Join")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Join \(meeting.title)")
    }
}

/// The card's beats. See `NotchInteractionState` for why this isn't `@State`.
private final class MeetingReveal: ObservableObject {
    @Published var risen = false
    @Published var text = false
    @Published var ring = false
    @Published var join = false

    private var steps: [DispatchWorkItem] = []

    /// Almost all the way at once, then a gentle glide to a stop.
    private static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)

    func run() {
        cancel()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settle()
            return
        }
        step(at: 0.05, Self.rise) { $0.risen = true }
        step(at: 0.25, .easeOut(duration: 0.4)) { $0.text = true }
        step(at: 0.35, .easeOut(duration: 0.9)) { $0.ring = true }
        step(at: 0.6, .spring(response: 0.45, dampingFraction: 0.85)) { $0.join = true }
    }

    func settle() {
        risen = true; text = true; ring = true; join = true
    }

    func cancel() {
        steps.forEach { $0.cancel() }
        steps.removeAll()
    }

    private func step(at time: TimeInterval, _ animation: Animation, _ change: @escaping (MeetingReveal) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(animation) { change(self) }
        }
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: work)
    }
}
