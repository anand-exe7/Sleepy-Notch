import SwiftUI

/// What a peek is about.
enum PeekContent: Equatable {
    case track(TrackChange)
    case power(PowerEvent)
    case headphones(HeadphoneEvent)
    case keyboard(KeyboardEvent)
    case meeting(MeetingReminder)
    case copied(ClipboardPreview)
    /// The camera or mic just switched on: a short notice that then shrinks
    /// into its bubble beside the notch.
    case privacy(PrivacyNotice)
    /// An activity opened from its bubble (see `ActivityManager.expand`).
    case activity(ActivityKind)
    /// A countdown ran out.
    case timerDone(minutes: Int, sleep: Bool)
    /// The bedtime reminder.
    case windDown(bedtime: String)
    /// The sleep timer ended and the music paused.
    case goodNight
    /// The 20-20-20 reminder.
    case eyeBreak
    /// The volume, brightness or keyboard backlight changed.
    case hud(HUDReading)
    /// A line of text from a script.
    case message(String)
    /// A download finished.
    case downloadDone(name: String)
    /// An agent needs input or has finished.
    case agentNotice(AgentNotice)
    /// Once per startup (see `WelcomeCoordinator`).
    case welcome

    enum Category {
        case track, power, headphones, keyboard, meeting, copied, privacy, activity, timerDone, windDown, goodNight, eyeBreak, hud, message, downloadDone, agent, welcome
    }

    var category: Category {
        switch self {
        case .track: return .track
        case .power: return .power
        case .headphones: return .headphones
        case .keyboard: return .keyboard
        case .meeting: return .meeting
        case .copied: return .copied
        case .privacy: return .privacy
        case .activity: return .activity
        case .timerDone: return .timerDone
        case .windDown: return .windDown
        case .goodNight: return .goodNight
        case .eyeBreak: return .eyeBreak
        case .hud: return .hud
        case .message: return .message
        case .downloadDone: return .downloadDone
        case .agentNotice: return .agent
        case .welcome: return .welcome
        }
    }

    /// The activity this peek is about, which waits in the notch while it
    /// shows and shrinks into its bubble as it closes.
    var announces: ActivityKind? {
        switch self {
        case .power(let event): return event.kind == .pluggedIn ? .charging : nil
        case .privacy: return .privacy
        case .activity(let kind): return kind
        default: return nil
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
            case .unplugged, .fullyCharged: return 2.8
            }
        case .headphones(let event):
            // The product's entrance, then long enough to read the
            // batteries, which can arrive a moment late.
            return event.isConnected ? 5.8 : 2.8
        case .keyboard:
            // The key's press, then a beat to read it.
            return 1.9
        case .meeting:
            // Long enough to notice and reach for Join; it also stays while
            // the pointer is on it.
            return 10
        case .copied:
            return 1.8
        case .privacy:
            // Long enough to read, then it gets out of the way.
            return 2.2
        case .activity:
            return ActivityManager.autoCollapseDelay
        case .timerDone:
            return 3.2
        case .windDown:
            return 6
        case .eyeBreak:
            return 7
        case .hud:
            return 1.5
        case .message:
            return 3.2
        case .goodNight:
            // The pen writes for about 1.5 s; then a moment to read it.
            return 4.6
        case .downloadDone:
            return 3.2
        case .agentNotice(let notice):
            // Needing you waits a little longer than news of a finish.
            return notice.state == .needsInput ? 5 : notice.message != nil ? 3.0 : 3.2
        case .welcome:
            // The notch opening, the word writing itself (~2.4s), the line
            // under it (~0.9s), then a moment to see it all.
            return 4.7
        }
    }

    /// Height of the area that drops below the notch: one row, or for
    /// headphones the product beside its name and battery rings.
    var contentHeight: CGFloat {
        switch self {
        case .track: return TrackPeekView.contentHeight
        case .power: return ChargingPeekView.contentHeight
        case .headphones:
            return HeadphonePeekView.contentHeight
        case .keyboard: return KeyboardPeekView.contentHeight
        case .meeting: return MeetingPeekView.contentHeight
        case .copied: return 54
        case .privacy: return PrivacyNoticeView.contentHeight
        case .activity: return ActivityDetailView.contentHeight
        case .timerDone: return TimerDonePeekView.contentHeight
        case .windDown: return WindDownPeekView.contentHeight
        case .goodNight: return GoodNightPeekView.contentHeight
        case .eyeBreak: return EyeBreakPeekView.contentHeight
        case .hud: return HUDPeekView.contentHeight
        case .message: return MessagePeekView.contentHeight
        case .downloadDone: return DownloadDonePeekView.contentHeight
        case .agentNotice: return AgentNoticeView.contentHeight
        case .welcome: return WelcomePeekView.height
        }
    }

    /// How much wider than the notch the peek grows. A song change is a
    /// small, quick heads-up, so it stays compact, well inside the card's
    /// width, instead of spreading as wide as the other peeks.
    var extraWidth: CGFloat {
        if case .track = self { return 120 }
        if case .privacy = self { return 120 }
        if case .timerDone = self { return 120 }
        if case .windDown = self { return 190 }
        if case .goodNight = self { return 170 }
        if case .eyeBreak = self { return 200 }
        if case .hud = self { return 120 }
        if case .message = self { return 150 }
        if case .downloadDone = self { return 150 }
        if case .agentNotice(let notice) = self { return notice.message != nil ? 230 : 150 }
        // One compact row each: only as wide as what they say.
        if case .keyboard = self { return 56 }
        if case .copied = self { return 110 }
        // The same width as the music card, so it reads as the notch itself
        // opening rather than a banner.
        if case .welcome = self { return NotchMetrics.cardExtraWidth }
        return NotchMetrics.peekExtraWidth
    }

    /// Bottom corner radius: the shorter song peek gets a smaller one, in
    /// proportion with its height.
    var bottomRadius: CGFloat {
        if case .track = self { return 18 }
        if case .privacy = self { return 20 }
        if case .timerDone = self { return 20 }
        if case .windDown = self { return 28 }
        if case .goodNight = self { return 28 }
        if case .eyeBreak = self { return 26 }
        if case .hud = self { return 20 }
        if case .message = self { return 22 }
        if case .downloadDone = self { return 20 }
        if case .agentNotice = self { return 20 }
        if case .keyboard = self { return 20 }
        if case .copied = self { return 22 }
        if case .welcome = self { return WelcomePeekView.bottomRadius }
        return NotchMetrics.peekBottomRadius
    }

    /// Whether a peek posted while the card is open should wait and show
    /// once it closes. A song change is already visible in the open card.
    var waitsForCard: Bool {
        switch category {
        case .power, .headphones, .meeting, .privacy, .activity, .timerDone, .windDown, .goodNight, .eyeBreak, .hud, .message, .downloadDone, .agent, .welcome: return true
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
        // A finished timer is still worth seeing after the card closes.
        if case .timerDone = self { return 60 }
        // A bedtime reminder is still worth seeing a little late.
        if case .windDown = self { return 3 * 60 }
        if case .goodNight = self { return 60 }
        // A break reminder is stale once the next is nearly due.
        if case .eyeBreak = self { return 30 }
        if case .hud = self { return 2 }
        if case .message = self { return 30 }
        if case .downloadDone = self { return 30 }
        if case .agentNotice = self { return 60 }
        // Still a welcome however long the card or another peek holds it.
        if case .welcome = self { return 10 * 60 }
        // Headphones connecting is worth seeing after a song change or the
        // card: the batteries are still news.
        if case .headphones(let event) = self, event.isConnected { return 20 }
        return 6
    }

    /// Peeks that stage their own entrance, so the notch only fades them in.
    var revealsItself: Bool {
        switch self {
        case .welcome, .headphones, .power, .keyboard, .meeting, .activity, .windDown, .goodNight, .eyeBreak, .hud, .message: return true
        default: return false
        }
    }

    /// A peek with something to click. Hovering it holds it down instead of
    /// opening the card, and it stays until the pointer leaves.
    var isInteractive: Bool {
        if case .meeting = self { return true }
        // An opened activity stays while the pointer is on it.
        if case .activity = self { return true }
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
    /// The app just opened and the welcome is still to come: everything
    /// else waits in line until it has played (see `holdForWelcome`).
    @Published private(set) var welcomePending = false
    private var welcomeTimeout: DispatchWorkItem?

    private var pending: [Peek] = []
    private var dismissWork: DispatchWorkItem?
    private var nextWork: DispatchWorkItem?
    private var isHeld = false
    /// Song changes before this are already known: they come from the card
    /// that just closed (Next pressed in it, landing a moment after it shut).
    private var trackQuietUntil = Date.distantPast
    /// How long after the card closes a song change counts as the card's.
    private static let trackQuietAfterCard: TimeInterval = 2.5

    /// Called just before a peek folds away on its own, so the notch can
    /// close it the same way as the card (see `NotchView`).
    var willDismiss: (() -> Void)?
    /// Called just before a peek appears; returns how long to wait first,
    /// so the notch can get ready while it's still closed (the welcome
    /// switches to glass).
    var willShow: ((PeekContent) -> TimeInterval)?

    /// Breathing room between peeks, so one folds up before the next drops.
    private static let gap: TimeInterval = 0.4

    private let power: PowerStateMonitor

    init(power: PowerStateMonitor) {
        self.power = power
    }

    func post(_ content: PeekContent) {
        guard power.isNotchVisible else { return }
        let peek = Peek(content: content)

        if case .track = content, Date() < trackQuietUntil { return }
        // The welcome goes first: anything else waits for it.
        if welcomePending && content != .welcome {
            enqueue(peek)
            return
        }
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

    /// A system HUD reading. While one is already up, the reading changes in
    /// place and the peek stays a moment longer, so holding a key doesn't
    /// restart it each step.
    func postHUD(_ reading: HUDReading) {
        if var peek = current, case .hud = peek.content, !isHeld {
            peek.content = .hud(reading)
            current = peek
            scheduleDismiss(at: Date().addingTimeInterval(PeekContent.hud(reading).duration))
            return
        }
        post(.hud(reading))
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
            trackQuietUntil = Date().addingTimeInterval(Self.trackQuietAfterCard)
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

    /// The welcome is on its way: hold every other peek until it has
    /// played, then show them in order. Gives up after `timeout` in case it
    /// never gets to show (the screen stayed locked, say).
    func holdForWelcome(timeout: TimeInterval = 20) {
        welcomePending = true
        welcomeTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.releaseWelcomeHold() }
        welcomeTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    /// The welcome is done (or isn't coming): what waited behind it shows
    /// now, counted as fresh, since it only waited for the welcome.
    func releaseWelcomeHold() {
        guard welcomePending else { return }
        welcomePending = false
        welcomeTimeout?.cancel()
        welcomeTimeout = nil
        pending = pending.map { Peek(content: $0.content) }
        if current == nil { scheduleNext() }
    }

    /// Shows `content` at once, replacing whatever peek is up: a click on a
    /// bubble. With the card open it goes first in line instead.
    func postNow(_ content: PeekContent) {
        guard power.isNotchVisible, !welcomePending else { return }
        let peek = Peek(content: content)
        pending.removeAll { $0.content.category == content.category }
        if isHeld {
            pending.insert(peek, at: 0)
            return
        }
        show(peek)
    }

    /// Whether a peek matching `predicate` is waiting its turn.
    func hasPending(_ predicate: (PeekContent) -> Bool) -> Bool {
        pending.contains { predicate($0.content) }
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
        if let lead = willShow?(peek.content), lead > 0 {
            let work = DispatchWorkItem { [weak self] in self?.present(peek) }
            nextWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + lead, execute: work)
            return
        }
        present(peek)
    }

    private func present(_ peek: Peek) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            current = peek
        }
        scheduleDismiss(at: Date().addingTimeInterval(peek.content.duration))
    }

    private func dismiss() {
        dismissAt = nil
        if current?.content == .welcome { releaseWelcomeHold() }
        willDismiss?()
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
        // While the welcome is due, only it may show.
        if welcomePending {
            if let index = pending.firstIndex(where: { $0.content == .welcome }) {
                show(pending.remove(at: index))
            }
            return
        }
        guard !pending.isEmpty else { return }
        show(pending.removeFirst())
    }
}
