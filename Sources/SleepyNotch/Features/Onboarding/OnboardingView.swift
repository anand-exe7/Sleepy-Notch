import SwiftUI

/// The first-launch setup: one page at a time, each sliding in with its
/// pieces rising after it, a progress line at the top and Back / Continue
/// at the bottom (Return moves on).
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    static let size = CGSize(width: 780, height: 640)
    /// The width every page is laid out in.
    static let contentWidth: CGFloat = 600

    var body: some View {
        ZStack(alignment: .top) {
            // Over the window's frosted desktop: dark enough to read on,
            // light enough that the desktop's colour comes through.
            OnboardingStyle.background.opacity(0.84)
            // A faint light from the top, where the notch is.
            RadialGradient(
                colors: [Color.white.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
            // The window wears a notch of its own, holding the progress.
            notch
            VStack(spacing: 0) {
                Spacer().frame(height: 46)
                ZStack {
                    page(model.step)
                        .id(model.step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { model.appear() }
    }

    private var pageTransition: AnyTransition {
        let edge: Edge = model.forward ? .trailing : .leading
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: edge)).animation(.spring(response: 0.55, dampingFraction: 0.9)),
            removal: .opacity.combined(with: .move(edge: edge == .trailing ? .leading : .trailing)).animation(.easeIn(duration: 0.25))
        )
    }

    @ViewBuilder
    private func page(_ step: OnboardingStep) -> some View {
        let shown = model.revealed == step
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep(model: model, shown: shown)
            case .hello:
                OnboardingHelloStep(model: model, preferences: model.preferences, shown: shown)
            case .pages:
                OnboardingPagesStep(preferences: model.preferences, shown: shown)
            case .player:
                OnboardingPlayerStep(model: model, preferences: model.preferences, shown: shown)
            case .lockScreen:
                OnboardingLockStep(model: model, preferences: model.preferences, shown: shown)
            case .notch:
                OnboardingNotchStep(preferences: model.preferences, shown: shown)
            case .allow:
                OnboardingAllowStep(model: model, preferences: model.preferences, permissions: model.permissions, shown: shown)
            }
        }
        .frame(width: Self.contentWidth)
    }

    /// A small black notch hanging from the window's top edge, like the
    /// real one, with the progress inside it.
    private var notch: some View {
        ZStack {
            NotchShape(bottomRadius: 13, topFlare: 7)
                .fill(Color.black)
            progress
                .padding(.bottom, 2)
        }
        .frame(width: 196, height: 32)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    /// One short segment per page; the done ones and the current one lit.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(Color.white.opacity(step == model.step ? 1 : step.rawValue < model.step.rawValue ? 0.55 : 0.18))
                    .frame(width: step == model.step ? 28 : 12, height: 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.step)
        .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome {
                Button("Back") { model.back() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .focusable(false)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                model.next()
            } label: {
                HStack(spacing: 6) {
                    Text(model.step.isLast ? "Start Sleepy Notch" : "Continue")
                    Image(systemName: model.step.isLast ? "sparkles" : "arrow.right")
                        .font(.system(size: 11.5, weight: .bold))
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .focusable(false)
            .keyboardShortcut(.defaultAction)
        }
        .overlay {
            Text("\(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.35))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.2), value: model.step)
    }
}
