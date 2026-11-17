import SwiftUI

/// The setup's shared pieces: the rise-in, the type, the sample screen with
/// its notch, the option cards and chips, and the buttons.
enum OnboardingStyle {
    /// Things rise on this curve and play once.
    static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.75)
    static let select = Animation.spring(response: 0.32, dampingFraction: 0.8)

    static let background = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let surface = Color.white.opacity(0.055)
    static let surfaceHover = Color.white.opacity(0.085)
    static let stroke = Color.white.opacity(0.1)
    static let selectedStroke = Color.white.opacity(0.92)

    static let title = Font.system(size: 28, weight: .bold)
    static let subtitle = Font.system(size: 14, weight: .regular)
    static let heading = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12.5)
    static let small = Font.system(size: 11.5)
}

/// A piece of a page that rises into place, `order` beats after the page
/// arrives, and fades quickly as the page leaves.
private struct Rise: ViewModifier {
    let order: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .animation(
                shown ? OnboardingStyle.rise.delay(0.04 + Double(order) * 0.07) : .easeOut(duration: 0.16),
                value: shown
            )
    }
}

extension View {
    func rise(_ order: Int, _ shown: Bool) -> some View {
        modifier(Rise(order: order, shown: shown))
    }
}

/// A page's big title and the line under it.
struct OnboardingHeader: View {
    /// A small label above the title: the page's symbol and name.
    var symbol: String?
    var eyebrow: String?
    let title: String
    let subtitle: String
    let shown: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let eyebrow {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                    }
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                }
                .foregroundColor(.white.opacity(0.62))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.bottom, 2)
                .rise(0, shown)
            }
            Text(title)
                .font(OnboardingStyle.title)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .rise(0, shown)
            Text(subtitle)
                .font(OnboardingStyle.subtitle)
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 540)
                .rise(1, shown)
        }
    }
}

/// A sample of the top of a Mac's screen: a soft wallpaper, the menu bar's
/// strip and the notch hanging from it, holding `content` below the camera.
struct ScreenPreview<Content: View>: View {
    var notchWidth: CGFloat = 220
    var notchHeight: CGFloat = 96
    var cornerRadius: CGFloat = 14
    /// The glass finish: black by the camera, melting into a blur of the
    /// wallpaper along the bottom.
    var glass = false
    @ViewBuilder let content: () -> Content

    private var shape: some View {
        NotchShape(bottomRadius: min(30, notchHeight * 0.32), topFlare: 8)
            .frame(width: notchWidth + 16, height: notchHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            if glass {
                Wallpaper()
                    .blur(radius: 16)
                    .overlay(Color.black.opacity(0.22))
                    .overlay(Color.white.opacity(0.04))
                    .mask(alignment: .top) { shape }
                    .transition(.opacity)
            }
            NotchShape(bottomRadius: min(30, notchHeight * 0.32), topFlare: 8)
                .fill(glass
                    ? LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.42), .init(color: .black.opacity(0.08), location: 1)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom))
                .frame(width: notchWidth + 16, height: notchHeight)
            content()
                .frame(width: notchWidth, height: notchHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(OnboardingStyle.stroke, lineWidth: 1)
        )
    }
}

/// A calm, dusky wallpaper for the samples, with soft shapes so the glass
/// finish has something to blur.
struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.16, blue: 0.3),
                    Color(red: 0.3, green: 0.2, blue: 0.38),
                    Color(red: 0.62, green: 0.36, blue: 0.36),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                Circle()
                    .fill(Color(red: 0.95, green: 0.62, blue: 0.42).opacity(0.55))
                    .frame(width: proxy.size.width * 0.5)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.62)
                    .blur(radius: 30)
                Circle()
                    .fill(Color(red: 0.36, green: 0.52, blue: 0.95).opacity(0.5))
                    .frame(width: proxy.size.width * 0.42)
                    .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.4)
                    .blur(radius: 28)
            }
        }
    }
}

/// A large choice with a picture on top, a title and a line under it.
struct OptionCard<Preview: View>: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        HoverReader { hovering in
            card(hovering: hovering)
        }
    }

    private func card(hovering: Bool) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(OnboardingStyle.heading)
                            .foregroundColor(.white)
                        Text(detail)
                            .font(OnboardingStyle.small)
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    SelectionMark(selected: selected)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected || hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        selected ? OnboardingStyle.selectedStroke : Color.white.opacity(hovering ? 0.22 : 0.1),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .lifted(hovering)
            .animation(OnboardingStyle.select, value: selected)
        }
        .buttonStyle(OnboardingPressStyle())
    }
}

/// Whether the pointer is over `content`, for hover looks. The flag lives
/// in a small object (no `@State` in this project).
struct HoverReader<Content: View>: View {
    @StateObject private var flag = HoverFlag()
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(flag.on)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.16)) { flag.on = inside }
            }
    }
}

final class HoverFlag: ObservableObject {
    @Published var on = false
}

extension View {
    /// Rises a touch toward the pointer: a hair larger, with a soft shadow.
    func lifted(_ on: Bool) -> some View {
        self
            .scaleEffect(on ? 1.015 : 1)
            .shadow(color: .black.opacity(on ? 0.35 : 0), radius: on ? 14 : 0, y: on ? 6 : 0)
    }
}

/// The round tick of a chosen option (an empty ring when not chosen).
struct SelectionMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.28), lineWidth: 1.5)
            Circle()
                .fill(Color.white)
                .scaleEffect(selected ? 1 : 0.2)
                .opacity(selected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.black)
                .scaleEffect(selected ? 1 : 0.4)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .animation(OnboardingStyle.select, value: selected)
    }
}

/// A small pill in a row of choices ("Glass", "Black").
struct ChoiceChip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HoverReader { hovering in
            chip(hovering: hovering)
        }
    }

    private func chip(hovering: Bool) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.white : hovering ? OnboardingStyle.surfaceHover : OnboardingStyle.surface))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(hovering ? 0.22 : 0.1), lineWidth: 1))
            .animation(OnboardingStyle.select, value: selected)
        }
        .buttonStyle(OnboardingPressStyle())
    }
}

/// A labelled switch in the setup's own look.
struct OnboardingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                if let detail {
                    Text(detail)
                        .font(OnboardingStyle.small)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .focusable(false)
        }
    }
}

/// The white capsule that moves the setup on. Brightens and lifts a
/// touch under the pointer.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 22)
            .frame(minWidth: 128, minHeight: 36)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1)))
            .shadow(color: Color.white.opacity(0.12), radius: 12, y: 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// The quiet "Back".
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.5 : 0.72))
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Capsule().fill(OnboardingStyle.surface))
            .contentShape(Capsule())
    }
}

/// A gentle press for the setup's larger buttons.
struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
