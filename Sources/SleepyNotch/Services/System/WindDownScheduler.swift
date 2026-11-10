import AppKit

/// The bedtime reminder's clock: one one-shot timer for the next time the
/// reminder is due, set again after it fires.
///
/// Nothing runs between. It works on wall-clock time (a Mac that sleeps
/// through the hour still reminds at the right time, and the system clock or
/// time zone changing re-plans it). It is re-planned on wake and unlock, and
/// a reminder that comes due while the notch can't be seen is skipped rather
/// than shown late.
@MainActor
final class WindDownScheduler {
    /// Called when the reminder is due, with the bedtime to show.
    var onDue: ((String) -> Void)?
    /// Whether anyone can see the notch right now.
    var canShow: () -> Bool = { true }

    private var minutes: Int?
    private var work: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    /// Sets the time (minutes after midnight), or switches it off with nil.
    func schedule(minutesAfterMidnight: Int?) {
        minutes = minutesAfterMidnight
        plan()
        if minutes != nil { observe() } else { stopObserving() }
    }

    /// Time of day as a short label, e.g. "11:00 PM".
    static func label(forMinutes minutes: Int) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar.current.date(from: parts) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Planning

    private func plan(now: Date = Date()) {
        work?.cancel()
        work = nil
        guard let minutes, let due = Self.nextDate(minutes: minutes, after: now) else { return }
        let label = Self.label(forMinutes: minutes)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.canShow() { self.onDue?(label) }
            // The next one is tomorrow's.
            self.plan(now: Date().addingTimeInterval(1))
        }
        work = item
        // Wall-clock time keeps counting while the Mac sleeps.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + due.timeIntervalSince(now), execute: item)
    }

    /// The next time the clock reads `minutes` after midnight.
    static func nextDate(minutes: Int, after date: Date) -> Date? {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return Calendar.current.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
    }

    // MARK: - Re-planning

    private func observe() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let replan: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.plan() }
        }
        observers = [
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: replan),
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: replan),
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: replan),
            NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: replan),
        ]
    }

    private func stopObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspace.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }
}
