import SwiftUI

/// What a peek is about.
enum PeekContent: Equatable {
    case track(TrackChange)
    case power(PowerEvent)
    case headphones(HeadphoneEvent)
    case keyboard(KeyboardEvent)
    case meeting(MeetingReminder)
    case copied(ClipboardPreview)

    enum Category {
        case track, power, headphones, keyboard, meeting, copied
    }

    var category: Category {
        switch self {
        case .track: return .track
        case .power: return .power
        case .headphones: return .headphones
        case .keyboard: return .keyboard
        case .meeting: return .meeting
        case .copied: return .copied
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
            // Long enough to watch the parts settle and the rings fill —
            // which can start a moment late, when the levels arrive.
            return event.isConnected ? 5.2 : 2.6
        case .keyboard:
            return 1.5
        case .meeting:
            // Long enough to notice and reach for Join; it also stays while
            // the pointer is on it.
            return 10
        case .copied:
            return 1.8
        }
    }

    /// Height of the area that drops below the notch: one row, or for
    /// headphones the name over a row of battery rings.
    var contentHeight: CGFloat {
        switch self {
        case .track: return 56
        case .power: return 60
        case .headphones(let event):
            // Disconnected shows no levels, so no row of numbers.
            return event.isConnected ? 140 : 116
        case .keyboard: return 66
        case .meeting: return 66
        case .copied: return 54
        }
    }

    /// Whether a peek posted while the card is open should wait and show
    /// once it closes. A song change is already visible in the open card.
    var waitsForCard: Bool {
        switch category {
        case .power, .headphones, .meeting: return true
        // A song change is already in the card; a key or a copy is stale
        // by the time it closes.
        case .track, .keyboard, .copied: return false
        }
    }

    /// How long a peek can wait in the queue (behind the open card, or
    /// another peek) and still be worth showing. A meeting reminder stays
    /// useful until close to the start; most news is stale in seconds.
    var maxQueueAge: TimeInterval {
        if case .meeting = self { return 4 * 60 }
        return 6
    }

    /// A peek with something to click. Hovering it holds it down instead of
    /// opening the card, and it stays until the pointer leaves.
    var isInteractive: Bool {
        if case .meeting = self { return true }
        return false
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
    @Published private(set) var current: Peek?

    private var pending: [Peek] = []
    private var dismissWork: DispatchWorkItem?
    private var nextWork: DispatchWorkItem?
    private var isHeld = false

    /// Breathing room between peeks, so one folds up before the next drops.
    private static let gap: TimeInterval = 0.4

    private let power: PowerStateMonitor

    init(power: PowerStateMonitor) {
        self.power = power
    }

    func post(_ content: PeekContent) {
        guard power.isNotchVisible else { return }
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

    /// The pointer moved onto or off an interactive peek: hold it while the
    /// pointer is on it, then fold it up shortly after it leaves.
    func setPointerOver(_ over: Bool) {
        guard current?.content.isInteractive == true else { return }
        if over {
            dismissWork?.cancel()
            dismissAt = .distantFuture
        } else {
            scheduleDismiss(at: Date().addingTimeInterval(Self.leaveGrace))
        }
    }

    /// Folds the current peek up now, e.g. after its button was used.
    func dismissCurrent() {
        guard current != nil else { return }
        dismissWork?.cancel()
        dismiss()
    }

    private static let leaveGrace: TimeInterval = 1.5

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
        // Levels that arrive late still get their full fill and a beat to
        // be read, rather than the peek folding up mid-sweep.
        extendDismissal(toAtLeast: Self.batteryReadTime)
    }

    /// How long the peek stays down after its battery levels arrive.
    private static let batteryReadTime: TimeInterval = 2.8
    private var dismissAt: Date?

    private func extendDismissal(toAtLeast seconds: TimeInterval) {
        let target = Date().addingTimeInterval(seconds)
        guard let dismissAt, target > dismissAt else { return }
        scheduleDismiss(at: target)
    }

    private func scheduleDismiss(at date: Date) {
        dismissWork?.cancel()
        dismissAt = date
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow), execute: work)
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
        scheduleDismiss(at: Date().addingTimeInterval(peek.content.duration))
    }

    private func dismiss() {
        dismissAt = nil
        withAnimation(NotchView.closeMotion) {
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
        pending.removeAll { now.timeIntervalSince($0.postedAt) > $0.content.maxQueueAge }
        guard !pending.isEmpty else { return }
        show(pending.removeFirst())
    }
}
