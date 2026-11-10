import SwiftUI

/// The red dot macOS itself uses for "recording".
struct RecordingDot: View {
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(Theme.Status.critical)
            .frame(width: size, height: size)
            .accessibilityLabel("Screen recording")
    }
}

/// Beside the notch when the recording is the main activity: how long it has
/// been going, counted up by the system.
struct RecordingWingText: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(86_400), countsDown: false, showsHours: false)
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundColor(Theme.Text.primary)
            .lineLimit(1)
            .accessibilityLabel("Recording time")
    }
}

/// Opened from its bubble: the recording time, big.
struct RecordingDetail: View {
    let since: Date?

    var body: some View {
        HStack(spacing: 14) {
            RecordingDot(size: 14)
            VStack(alignment: .leading, spacing: 2) {
                if let since {
                    Text(timerInterval: since...since.addingTimeInterval(86_400), countsDown: false, showsHours: false)
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.primary)
                }
                Text("Screen recording")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}
