import SwiftUI

/// The Widgets tab: a month, today's weather, a Pomodoro timer and the
/// machine's load, side by side in the open card. Nothing here runs while
/// the card is closed: the weather is fetched when it opens (if its reading
/// is old), the events are read once, and the stats tick only while it is
/// on screen.
struct WidgetsView: View {
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var glance: CalendarGlance
    @EnvironmentObject private var pomodoro: PomodoroService
    @EnvironmentObject private var timers: TimerService

    @Environment(\.notchCardActive) private var cardActive
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CalendarWidget(glance: glance)
                .frame(width: 128)
            VStack(alignment: .leading, spacing: 7) {
                WeatherWidget(weather: weather)
                PomodoroWidget(pomodoro: pomodoro, timers: timers)
                // Its own view, so a tick of the stats redraws only this row.
                StatsWidget()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .frame(width: width, height: 106, alignment: .top)
        .onAppear { open() }
        .onChange(of: cardActive) { active in
            if active { open() }
        }
    }

    private func open() {
        guard cardActive else { return }
        glance.refresh()
        Task { await weather.refresh() }
    }
}

// MARK: - Calendar

private struct CalendarWidget: View {
    @ObservedObject var glance: CalendarGlance

    private static let cellWidth: CGFloat = 128.0 / 7
    private static let cellHeight: CGFloat = 11.5

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                Button(action: glance.showToday) {
                    Text(glance.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                arrow("chevron.left") { glance.step(-1) }
                arrow("chevron.right") { glance.step(1) }
            }
            .frame(height: 14)

            HStack(spacing: 0) {
                ForEach(Array(glance.weekdayInitials.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                        .frame(width: Self.cellWidth, height: 10)
                }
            }

            ForEach(Array(glance.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar, \(glance.title)")
    }

    @ViewBuilder
    private func cell(_ day: Int?) -> some View {
        ZStack {
            if let day {
                if day == glance.today {
                    Circle().fill(Color.white).frame(width: 13, height: 13)
                }
                Text("\(day)")
                    .font(.system(size: 9, weight: day == glance.today ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundColor(day == glance.today ? .black : Theme.Text.secondary)
                if glance.eventDays.contains(day) && day != glance.today {
                    Circle()
                        .fill(Theme.Text.primary)
                        .frame(width: 2.5, height: 2.5)
                        .offset(y: 7)
                }
            }
        }
        .frame(width: Self.cellWidth, height: Self.cellHeight)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(Theme.Text.tertiary)
                .frame(width: 16, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

// MARK: - Weather

private struct WeatherWidget: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        HStack(spacing: 8) {
            if let reading = weather.reading {
                let look = WeatherService.describe(code: reading.code, isDay: reading.isDay)
                Image(systemName: look.symbol)
                    .font(.system(size: 17))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(Theme.Text.primary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text("\(Int(reading.temperature.rounded()))°")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                        Text(look.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.Text.primary)
                    Text("\(reading.placeName.components(separatedBy: ",").first ?? reading.placeName) · H \(Int(reading.high.rounded()))° L \(Int(reading.low.rounded()))°")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.tertiary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 17))
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(weather.place == nil ? "Set a city" : (weather.isLoading ? "Loading…" : "No weather yet"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Text.secondary)
                    Text(weather.place == nil ? "Settings → Widgets" : (weather.problem ?? " "))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pomodoro

private struct PomodoroWidget: View {
    @ObservedObject var pomodoro: PomodoroService
    @ObservedObject var timers: TimerService

    var body: some View {
        let session = timers.session
        let round = session?.pomodoro
        HStack(spacing: 8) {
            Image(systemName: session?.symbol ?? "target")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                if let session {
                    Text(timerInterval: session.start...session.end, countsDown: true, showsHours: false)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.primary)
                } else {
                    Text("Focus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                }
                Text(subtitle(session: session, round: round))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Theme.Text.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if round != nil {
                pill("Skip") { pomodoro.skip() }
                Button { pomodoro.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.Text.secondary)
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Stop")
            } else if session == nil {
                pill("Start") { pomodoro.startFocus() }
            }
        }
        .frame(height: 30)
    }

    private func subtitle(session: TimerSession?, round: PomodoroPhase?) -> String {
        if let round {
            return round == .focus ? "Focus · \(pomodoro.completedToday + 1)" : "Break"
        }
        if let session { return "\(session.title) is running" }
        return pomodoro.completedToday == 0 ? "\(Int(pomodoro.focusMinutes)) min rounds" : "\(pomodoro.completedToday) done today"
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.primary)
                .padding(.horizontal, 11)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .fixedSize()
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

// MARK: - Stats

private struct StatsWidget: View {
    @EnvironmentObject private var stats: SystemStatsSampler
    @Environment(\.notchCardActive) private var cardActive

    var body: some View {
        HStack(spacing: 12) {
            bar("CPU", fraction: stats.cpu, text: stats.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
            bar("MEM", fraction: stats.memory, text: stats.memoryUsedGB.map { String(format: "%.1f GB", $0) } ?? "–")
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
        // Sampling lasts exactly as long as this row is on screen in an open card.
        .onAppear { if cardActive { stats.start() } }
        .onChange(of: cardActive) { active in
            if active { stats.start() } else { stats.stop() }
        }
        .onDisappear { stats.stop() }
    }

    private func bar(_ label: String, fraction: Double?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.Text.tertiary)
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(3, proxy.size.width * CGFloat(fraction ?? 0)))
                }
            }
            .frame(height: 3)
        }
    }
}
