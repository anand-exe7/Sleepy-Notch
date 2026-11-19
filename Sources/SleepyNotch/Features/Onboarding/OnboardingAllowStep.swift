import SwiftUI

/// The last page: the permissions the choices need, each asked only when
/// its Allow is clicked, then Start.
struct OnboardingAllowStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: HUDPreferences
    @ObservedObject var permissions: OnboardingPermissions
    let shown: Bool

    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let state: PermissionState
        var optional = false
        let ask: () -> Void
    }

    private var rows: [Row] {
        var list: [Row] = [
            Row(id: "music", symbol: "music.note", title: "Control Music and Spotify",
                detail: "See the song that's playing, and play, pause and skip it",
                state: permissions.music, ask: permissions.askMusic),
        ]
        if preferences.widgets || preferences.meetingReminders {
            list.append(Row(id: "calendar", symbol: "calendar", title: "Calendar",
                            detail: "Your events on the card, and a reminder before meetings",
                            state: permissions.calendar, ask: permissions.askCalendar))
        }
        if preferences.voiceWaves {
            list.append(Row(id: "mic", symbol: "mic.fill", title: "Microphone",
                            detail: "Voice waves while another app uses the mic. Nothing is recorded",
                            state: permissions.microphone, ask: permissions.askMicrophone))
        }
        if preferences.keyboardPeek {
            list.append(Row(id: "accessibility", symbol: "accessibility", title: "Accessibility",
                            detail: "Lets the notch notice Caps Lock",
                            state: permissions.accessibility, optional: true, ask: permissions.askAccessibility))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                step: .allow,
                title: model.firstName.map { "Almost done, \($0)" } ?? "Almost done",
                subtitle: "Your choices need these. macOS asks for each, and nothing leaves your Mac.",
                shown: shown
            )
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                        .rise(2 + index, shown)
                }
            }
            Label("Click Start and the notch says hello. You can change these later in System Settings.", systemImage: "info.circle")
                .font(OnboardingStyle.small)
                .foregroundColor(OnboardingStyle.tertiaryText)
                .frame(maxWidth: .infinity)
                .rise(2 + rows.count, shown)
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.09)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(OnboardingStyle.heading)
                        .foregroundColor(.white)
                    if row.optional {
                        Text("Optional")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                Text(row.detail)
                    .font(OnboardingStyle.small)
                    .foregroundColor(OnboardingStyle.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            control(row)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OnboardingStyle.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OnboardingStyle.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private func control(_ row: Row) -> some View {
        Group {
            switch row.state {
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Status.charging)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .asking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if row.id == "accessibility" {
                        smallButton("Open Settings", action: row.ask)
                    }
                }
            case .later:
                Text("Asked on first song")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.trailing)
            case .denied:
                smallButton("Open Settings", action: row.ask)
            case .notAsked:
                Button("Allow", action: row.ask)
                    .buttonStyle(AllowButtonStyle())
            }
        }
        .frame(minWidth: 110, alignment: .trailing)
        .animation(OnboardingStyle.select, value: row.state)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .controlSize(.small)
    }
}

/// The white "Allow" pill on each row.
private struct AllowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(Capsule())
    }
}
