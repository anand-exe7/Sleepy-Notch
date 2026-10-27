import SwiftUI

/// A white symbol on a coloured rounded square, the icon style System
/// Settings uses in its sidebar and rows.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// The box at the top of each pane: a large icon, the pane's name, and a
/// sentence about what it controls.
struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(spacing: 6) {
            SettingsIcon(symbol: pane.symbol, color: pane.color, size: 52)
                .padding(.bottom, 4)
            Text(pane.title)
                .font(.title3.weight(.semibold))
            Text(pane.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
    }
}

/// A row's label: its icon, its name, and an optional line of detail
/// underneath in secondary text.
struct SettingsRowLabel: View {
    let title: String
    var detail: String?
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: symbol, color: color, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A row with its control on the right, centred against the label the way
/// System Settings does it. A form's own `Toggle` row pins the control to
/// the title line instead, which looks off once there's a line of detail.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    let symbol: String
    let color: Color
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 16) {
            SettingsRowLabel(title: title, detail: detail, symbol: symbol, color: color)
            Spacer(minLength: 0)
            control()
        }
    }
}

/// An on/off row with System Settings' small switch on the right.
struct SettingsToggle: View {
    let title: String
    var detail: String?
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail, symbol: symbol, color: color) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}
