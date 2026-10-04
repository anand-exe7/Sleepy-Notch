import SwiftUI

/// What a peek is about.
enum PeekContent: Equatable {
    case track(TrackChange)
    case power(PowerEvent)
    case headphones(HeadphoneEvent)

    enum Category {
        case track, power, headphones
    }

    var category: Category {
        switch self {
        case .track: return .track
        case .power: return .power
        case .headphones: return .headphones
        }
    }

    /// How long the peek stays down before folding back up.
    var duration: TimeInterval {
        switch self {
        case .track:
            return 2.6
        case .power(let event):
            switch event.kind {
            case .pluggedIn: return 3.4
            case .low: return 3.0
            case .unplugged, .fullyCharged: return 2.4
            }
        case .headphones(let event):
            return event.isConnected ? 3.6 : 2.2
        }
    }

    /// Whether a peek posted while the card is open should wait and show
    /// once it closes. A song change is already visible in the open card.
    var waitsForCard: Bool {
        category != .track
    }
}

struct Peek: Identifiable, Equatable {
    let id = UUID()
    var content: PeekContent
    let postedAt = Date()
}

/// Shows brief "peeks" — the notch dropping down for a few seconds to say
/// something happened — one at a time.
///
/// - A newer peek of the same kind replaces the one on screen (unplugging
///   right after plugging in shows only the latest).
/// - While the card is open the notch is busy: peeks wait, and show after it
///   closes if they're still fresh.
/// - Nothing shows while nobody can see the notch (display asleep, locked).
///
/// Each peek is a single one-shot timer; nothing runs between peeks.
@MainActor
final class PeekCenter: ObservableObject {
    static let shared = PeekCenter()

    @Published private(set) var current: Peek?

    private var pending: [Peek] = []
    private var dismissWork: DispatchWorkItem?
    private var nextWork: DispatchWorkItem?
    private var isHeld = false

    /// A queued peek older than this is stale by the time it could show.
    private static let maxQueueAge: TimeInterval = 6
    /// Breathing room between peeks, so one folds up before the next drops.
    private static let gap: TimeInterval = 0.4

    private init() {}

    func post(_ content: PeekContent) {
        guard PowerStateMonitor.shared.isNotchVisible else { return }
        let peek = Peek(content: content)

        if isHeld {
            if content.waitsForCard { enqueue(peek) }
            return
        }
        if let current, current.content.category != content.category {
            enqueue(peek)
            return
        }
        show(peek)
    }

    /// The card opened (hover, pin, or a file dragged over) or closed.
    func setHeld(_ held: Bool) {
        guard held != isHeld else { return }
        isHeld = held
        if held {
            dismissWork?.cancel()
            nextWork?.cancel()
            // The card takes over the notch; the peek's news is superseded.
            current = nil
        } else {
            scheduleNext()
        }
    }

    /// Battery levels arrive a moment after the connect peek is already up.
    func attachBattery(_ battery: HeadphoneBattery, toHeadphonesNamed name: String) {
        guard var peek = current,
              case .headphones(var event) = peek.content,
              event.name == name, event.isConnected
        else { return }
        event.battery = battery
        peek.content = .headphones(event)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            current = peek
        }
    }

    // MARK: - Queue

    private func enqueue(_ peek: Peek) {
        pending.removeAll { $0.content.category == peek.content.category }
        pending.append(peek)
    }

    private func show(_ peek: Peek) {
        dismissWork?.cancel()
        nextWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            current = peek
        }
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peek.content.duration, execute: work)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
            current = nil
        }
        scheduleNext()
    }

    private func scheduleNext() {
        nextWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.showNextPending()
        }
        nextWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.gap, execute: work)
    }

    private func showNextPending() {
        guard !isHeld, current == nil else { return }
        let now = Date()
        pending.removeAll { now.timeIntervalSince($0.postedAt) > Self.maxQueueAge }
        guard !pending.isEmpty else { return }
        show(pending.removeFirst())
    }
}
