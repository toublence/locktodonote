import Foundation

/// Localized text the composer needs. Injected so the composer itself stays
/// free of presentation concerns and remains testable.
public struct DashboardStrings: Sendable {
    public let noEvents: String
    public let hiddenContent: String
    public let checkInApp: String
    public let dDayToday: String
    public let dPlusPrefix: String
    public let timePassed: String
    public let hoursMinutesRemaining: String
    public let remainingTasks: String

    public init(
        noEvents: String,
        hiddenContent: String,
        checkInApp: String,
        dDayToday: String,
        dPlusPrefix: String,
        timePassed: String,
        hoursMinutesRemaining: String,
        remainingTasks: String
    ) {
        self.noEvents = noEvents
        self.hiddenContent = hiddenContent
        self.checkInApp = checkInApp
        self.dDayToday = dDayToday
        self.dPlusPrefix = dPlusPrefix
        self.timePassed = timePassed
        self.hoursMinutesRemaining = hoursMinutesRemaining
        self.remainingTasks = remainingTasks
    }

    public var privacyStrings: PrivacyStrings {
        PrivacyStrings(
            checkInApp: checkInApp,
            hiddenContent: hiddenContent,
            timeOnly: checkInApp,
            remainingCount: { [remainingTasks] count in "\(remainingTasks) \(count)" }
        )
    }
}

/// Turns the card library into the snapshot the Lock Screen renders.
///
/// Ported from the Flutter `DashboardComposer`, including its quirks: text is
/// truncated to keep the ActivityKit payload small, todos cap at five, and
/// tomorrow is pre-composed so the widget can roll over at midnight without the
/// app running.
public struct DashboardComposer: Sendable {
    private let calendar: Calendar
    private let strings: DashboardStrings
    private let localeIdentifier: String

    public init(
        strings: DashboardStrings,
        calendar: Calendar = .current,
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.strings = strings
        self.calendar = calendar
        self.localeIdentifier = localeIdentifier
    }

    public func compose(
        cards: [Card],
        selectedDate: Date? = nil,
        settings: LockScreenSettings,
        privacyMode: PrivacyMode = .full,
        now: Date = Date()
    ) -> DashboardSnapshot {
        let selectedDay = calendar.startOfDay(for: selectedDate ?? now)
        let today = calendar.startOfDay(for: now)
        let calendarDays = buildCalendarDays(
            cards: cards,
            selectedDay: selectedDay,
            settings: settings,
            now: now
        )
        let selected = calendarDays.first { $0.id == FlutterDate.dateKey(selectedDay, calendar: calendar) }

        let memoCard = settings.showMemos ? selectMemoCard(cards) : nil
        let todoItems = settings.showTodos ? (selected?.todoItems ?? []) : []
        let memoItems = settings.showMemos ? (selected?.memoItems ?? []) : []
        // Recording a memo is not consent to display it. Keep the calendar's
        // complete history/counts, but publish only the selected display notes.
        let displayedMemoIDs = Set(cards.filter { $0.type == .quickNote && $0.showOnLockScreen }.map(\.id))
        let displayedMemos = memoItems.filter { displayedMemoIDs.contains($0.id) }

        let visibleTodos: [DashboardTodoItem]
        let visibleMemos: [DashboardMemoItem]
        switch privacyMode {
        case .full:
            visibleTodos = todoItems
            visibleMemos = displayedMemos
        case .titleOnly:
            // Checklist row text is content, not a card title. Memo titles may remain.
            visibleTodos = []
            visibleMemos = displayedMemos.map {
                DashboardMemoItem(id: $0.id, title: $0.title)
            }
        case .hidden, .countOnly:
            // Do not merely hide text in the view: keep private content out of
            // the ActivityKit and App Group payloads altogether.
            visibleTodos = []
            visibleMemos = []
        }

        let visibleCalendarDays = calendarDays.map { day in
            var day = day
            if privacyMode != .full {
                day.todoItems = []
                day.memoItems = []
            }
            return day
        }

        // Counts describe the selected day's real state, not the filtered view.
        let selectedItems = cards
            .filter { $0.type == .checklist && $0.day(calendar: calendar) == selectedDay }
            .flatMap(\.checklistItems)
        let doneCount = selectedItems.filter(\.isDone).count

        let countdownCard = cards.first {
            $0.type == .countdown && ($0.targetDateTime.map { $0 > now } ?? false)
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let preparedNextDay = buildCalendarDay(
            cards: cards,
            date: tomorrow,
            selectedDay: selectedDay,
            visibleMonth: calendar.component(.month, from: selectedDay),
            settings: settings,
            now: now
        )
        var visiblePreparedNextDay = preparedNextDay
        if privacyMode != .full {
            visiblePreparedNextDay.todoItems = []
            visiblePreparedNextDay.memoItems = []
        }

        return DashboardSnapshot(
            calendarTitle: shortDateText(now),
            calendarText: calendarText(countdownCard, now: now),
            calendarDate: "\(calendar.component(.day, from: now))",
            selectedDate: selectedDay,
            selectedDateText: shortDateText(selectedDay),
            monthText: nil,
            localeCode: localeIdentifier,
            calendarDays: visibleCalendarDays,
            preparedNextDay: visiblePreparedNextDay,
            memoTitle: settings.showMemos && (privacyMode == .full || privacyMode == .titleOnly)
                ? shortText(memoCard?.title)
                : nil,
            memoText: privacyMode == .full
                ? memoText(memoCard, privacyMode: privacyMode, settings: settings)
                : nil,
            memoId: privacyMode == .full && settings.showMemos ? memoCard?.id : nil,
            memoItems: Array(visibleMemos.prefix(5)),
            memoCount: memoItems.count,
            todayTitle: privacyMode == .hidden || privacyMode == .countOnly
                ? nil
                : shortText(memoCard?.title),
            todayText: privacyMode == .full
                ? shortText(memoCard?.displayText(strings: strings.privacyStrings), maxLength: 54)
                : nil,
            todoItems: Array(visibleTodos.prefix(5)),
            doneCount: doneCount,
            totalCount: selectedItems.count,
            lockScreenLayout: settings.template.rawValue,
            imageFileName: settings.activeImageFileName,
            showTodosOnLockScreen: settings.showTodos,
            showMemosOnLockScreen: settings.showMemos,
            showCompletedTodosOnLockScreen: settings.showCompletedTodos,
            textFontWeight: settings.textFontWeight,
            textScale: settings.textScale,
            countdownTitle: privacyMode == .full || privacyMode == .titleOnly
                ? shortText(countdownCard?.title)
                : nil,
            countdownText: privacyMode == .hidden
                ? nil
                : countdownText(countdownCard?.targetDateTime, now: now),
            ddayTitle: privacyMode == .full || privacyMode == .titleOnly
                ? shortText(settings.ddayTitle)
                : nil,
            ddayTargetDate: settings.ddayTargetDate,
            ddayText: ddayText(settings.ddayTargetDate, now: now),
            ddayMemo: privacyMode == .full
                ? shortText(settings.ddayMemo, maxLength: 54)
                : nil,
            shortcutInsertPriority: settings.shortcutInsertPriority.rawValue,
            selectedContentSection: settings.selectedContentSection.rawValue,
            privacyMode: privacyMode.rawValue,
            updatedAt: now
        )
    }

    // MARK: - Calendar

    private func buildCalendarDays(
        cards: [Card],
        selectedDay: Date,
        settings: LockScreenSettings,
        now: Date
    ) -> [DashboardCalendarDay] {
        guard
            let interval = calendar.dateInterval(of: .month, for: selectedDay),
            let dayRange = calendar.range(of: .day, in: .month, for: selectedDay)
        else { return [] }

        let month = calendar.component(.month, from: selectedDay)
        // Lock Screen calendars always use Sunday as the first column so the
        // app preview and Live Activity do not change with locale defaults.
        let leading = calendar.component(.weekday, from: interval.start) - 1
        let totalCells = ((leading + dayRange.count + 6) / 7) * 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: interval.start) else { return [] }

        return (0..<totalCells).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return buildCalendarDay(
                cards: cards,
                date: date,
                selectedDay: selectedDay,
                visibleMonth: month,
                settings: settings,
                now: now
            )
        }
    }

    private func buildCalendarDay(
        cards: [Card],
        date: Date,
        selectedDay: Date,
        visibleMonth: Int,
        settings: LockScreenSettings,
        now: Date
    ) -> DashboardCalendarDay {
        let day = calendar.startOfDay(for: date)
        let dayCards = cards.filter { $0.day(calendar: calendar) == day }

        var todoItems: [DashboardTodoItem] = []
        if settings.showTodos {
            for card in dayCards where card.type == .checklist {
                for item in card.checklistItems where settings.showCompletedTodos || !item.isDone {
                    todoItems.append(
                        DashboardTodoItem(
                            id: "\(card.id):\(item.id)",
                            text: shortText(item.displayText(calendar: calendar)) ?? item.text,
                            isDone: item.isDone
                        )
                    )
                }
            }
            // Tomorrow shows what is heading its way, so the midnight rollover
            // does not surprise the user with an empty card.
            if day == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                todoItems.append(contentsOf: projectedTodos(cards: cards, targetDay: day))
            }
        }

        let memoItems: [DashboardMemoItem] = settings.showMemos
            ? dayCards.filter { $0.type == .quickNote }.map {
                DashboardMemoItem(
                    id: $0.id,
                    title: shortText($0.title) ?? $0.title,
                    bodyPreview: shortText($0.displayText(strings: strings.privacyStrings), maxLength: 42)
                )
            }
            : []

        return DashboardCalendarDay(
            id: FlutterDate.dateKey(day, calendar: calendar),
            day: calendar.component(.day, from: day),
            weekday: weekdayText(day),
            isSelected: day == selectedDay,
            isToday: calendar.isDate(day, inSameDayAs: now),
            isCurrentMonth: calendar.component(.month, from: day) == visibleMonth,
            hasItems: !todoItems.isEmpty || !memoItems.isEmpty,
            todoItems: todoItems,
            memoItems: memoItems
        )
    }

    /// Unfinished todos from earlier days plus recurrences that are due, shown
    /// on tomorrow before the rollover actually creates them.
    private func projectedTodos(cards: [Card], targetDay: Date) -> [DashboardTodoItem] {
        let local = cards.filter { AppleReminderMirror.reminderID(from: $0.id) == nil }
        let rolled = CardMutations.rollOverIncompleteTodos(local, calendar: calendar, now: targetDay, idFactory: { "projected:rollover-\($0)" }).cards
        let generated = CardMutations.createRecurringTodosForToday(rolled, calendar: calendar, now: targetDay, idFactory: { "projected:repeat-\($0)" }).cards
        let existing = Set(cards.filter { $0.day(calendar: calendar) == targetDay }
            .flatMap { card in card.checklistItems.map { "\(card.id):\($0.id)" } })
        return generated.filter { $0.type == .checklist && $0.day(calendar: calendar) == targetDay }
            .flatMap { card in card.checklistItems.filter { !$0.isDone }.compactMap { item in
                let id = "\(card.id):\(item.id)"
                guard !existing.contains(id) else { return nil }
                return DashboardTodoItem(id: id, text: shortText(item.displayText(calendar: calendar)) ?? item.text)
            } }
    }

    // MARK: - Selection helpers

    private func selectMemoCard(_ cards: [Card]) -> Card? {
        if let pinned = cards.first(where: { $0.type == .quickNote && $0.isPinned && $0.showOnLockScreen }) {
            return pinned
        }
        return cards.first { $0.type == .quickNote && $0.showOnLockScreen }
    }

    private func memoText(
        _ card: Card?,
        privacyMode: PrivacyMode,
        settings: LockScreenSettings
    ) -> String? {
        guard settings.showMemos else { return nil }
        guard privacyMode != .hidden else { return strings.hiddenContent }
        return shortText(card?.displayText(strings: strings.privacyStrings), maxLength: 54)
    }

    private func redact(_ items: [DashboardTodoItem]) -> [DashboardTodoItem] {
        items.map { DashboardTodoItem(id: $0.id, text: strings.hiddenContent, isDone: $0.isDone) }
    }

    private func redact(_ items: [DashboardMemoItem]) -> [DashboardMemoItem] {
        items.map { DashboardMemoItem(id: $0.id, title: strings.hiddenContent) }
    }

    // MARK: - Text

    /// Truncation keeps the ActivityKit payload inside its size budget.
    private func shortText(_ value: String?, maxLength: Int = 28) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }

    private func calendarText(_ countdown: Card?, now: Date) -> String {
        guard let countdown, let text = countdownText(countdown.targetDateTime, now: now) else {
            return strings.noEvents
        }
        guard let title = shortText(countdown.title) else { return text }
        return "\(title) · \(text)"
    }

    private func countdownText(_ target: Date?, now: Date) -> String? {
        guard let target else { return nil }
        let remaining = target.timeIntervalSince(now)
        if remaining < 0 { return strings.timePassed }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d %@", hours, minutes, strings.hoursMinutesRemaining)
        }
        return "\(minutes) min"
    }

    /// Day-granularity countdown: `D-n` ahead, `D+n` behind, localized on the day.
    public func ddayText(_ target: Date?, now: Date = Date()) -> String? {
        guard let target else { return nil }
        let todayStart = calendar.startOfDay(for: now)
        let targetStart = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0
        if days == 0 { return strings.dDayToday }
        if days > 0 { return "D-\(days)" }
        return "\(strings.dPlusPrefix)\(abs(days))"
    }

    private func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MdEEE")
        return formatter.string(from: date)
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}
