import SwiftUI

/// The pages of the first-launch setup, in order.
enum OnboardingStep: Int, CaseIterable {
    /// The big hello and the user's name.
    case welcome
    /// How the startup hello is written.
    case hello
    /// Which pages sit beside Music in the card.
    case pages
    /// How the music card looks.
    case player
    /// The lock screen player and everything it can do.
    case lockScreen
    /// What shows beside the closed notch.
    case notch
    /// The permissions those choices need, then start.
    case allow

    var isLast: Bool { self == Self.allCases.last }
}

/// The setup's own state: which page shows, the name being typed, and the
/// little replays its previews do when an option is clicked. The choices
/// themselves go straight into `HUDPreferences`, so they're already saved
/// when the setup ends (or if it's closed half way).
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep = .welcome
    /// The page whose pieces have risen in. Set a beat after the page
    /// arrives, so its pieces start hidden and rise one after another.
    @Published private(set) var revealed: OnboardingStep?
    /// Which way the pages slide.
    @Published private(set) var forward = true
    @Published var name: String
    /// Bumped to write a hello again (one take per ink).
    @Published private(set) var colourTake = 0
    @Published private(set) var whiteTake = 0
    /// The sample song's cover, moved on to show the cover change.
    @Published private(set) var coverIndex = 0
    /// Which stage of the lock screen player the sample shows.
    @Published var lockStage: LockSampleStage = .pill

    let preferences: HUDPreferences
    let permissions: OnboardingPermissions
    /// Closes the window and starts everything.
    var onFinish: () -> Void = {}

    init(preferences: HUDPreferences, permissions: OnboardingPermissions) {
        self.preferences = preferences
        self.permissions = permissions
        name = preferences.userName
    }

    /// The name as it will be used, or nil when none was given.
    var firstName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// The first page rises in once the window is up.
    func appear() {
        reveal(step, after: 0.25)
    }

    /// When the page last moved: a second press within a moment (Return
    /// reaching both the name field and the button) is the same press.
    private var lastMove = Date.distantPast

    private func settled() -> Bool {
        guard Date().timeIntervalSince(lastMove) > 0.35 else { return false }
        lastMove = Date()
        return true
    }

    func next() {
        guard settled() else { return }
        saveName()
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        if following == .allow { permissions.refresh() }
        go(to: following)
    }

    func back() {
        guard settled(), let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    func go(to target: OnboardingStep) {
        guard target != step else { return }
        forward = target.rawValue > step.rawValue
        revealed = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = target }
        reveal(target, after: 0.12)
    }

    private func reveal(_ target: OnboardingStep, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.step == target else { return }
            self.revealed = target
        }
    }

    func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferences.userName != trimmed { preferences.userName = trimmed }
    }

    // MARK: - Previews

    func chooseHello(colourful: Bool) {
        preferences.colourfulHello = colourful
        if colourful { colourTake += 1 } else { whiteTake += 1 }
    }

    func chooseCoverChange(_ style: ArtworkTransitionStyle) {
        preferences.artworkStyle = style
        playCoverChange()
    }

    /// The sample song moves on, so the chosen cover change plays once.
    func playCoverChange() {
        // A turn later, so the new style is in place before the cover moves.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.coverIndex = (self.coverIndex + 1) % 4
        }
    }
}

/// The three looks of the lock screen player the sample steps through.
enum LockSampleStage: Int, CaseIterable {
    case pill, card, art

    var title: String {
        switch self {
        case .pill: return "Pill"
        case .card: return "Player"
        case .art: return "Full screen"
        }
    }
}
