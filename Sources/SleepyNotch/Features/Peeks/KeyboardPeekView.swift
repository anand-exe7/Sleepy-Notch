import SwiftUI

/// "Caps Lock On", or the new keyboard layout: one short line.
struct KeyboardPeekView: View {
    let event: KeyboardEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Text.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }

    private var symbol: String {
        switch event {
        case .capsLock(let on): return on ? "capslock.fill" : "capslock"
        case .inputSource: return "globe"
        }
    }

    private var title: String {
        switch event {
        case .capsLock(let on): return on ? "Caps Lock On" : "Caps Lock Off"
        case .inputSource(let name): return name
        }
    }

    private var detail: String? {
        switch event {
        case .capsLock: return nil
        case .inputSource: return "Keyboard"
        }
    }
}
