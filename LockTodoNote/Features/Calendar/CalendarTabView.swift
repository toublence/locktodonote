import SwiftUI
import LockTodoNoteShared

/// Month grid plus the selected day's contents — the same split the Live
/// Activity's calendar template shows, so the two stay legible together.
struct CalendarTabView: View {
    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var selectionConfirmation: String?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthGrid
                selectedDayList
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
            .padding(.bottom, horizontalSizeClass == .regular ? 36 : 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .onChange(of: selectedDate) { date in
            guard settingsStore.settings.syncCalendarSelectionToLockScreen else { return }
            dashboard.selectedDate = date
            dashboard.publish()
            selectionConfirmation = String(
                format: appString(
                    localized: "calendar.lockScreenDateChanged",
                    defaultValue: "Lock Screen date changed to %@."
                ),
                appDateString(date)
            )
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                selectionConfirmation = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let selectionConfirmation {
                Text(selectionConfirmation)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    private var monthGrid: some View {
        MonthGrid(visibleMonth: $visibleMonth, selectedDate: $selectedDate)
    }

    private var selectedDayList: some View {
        SelectedDayList(
            date: selectedDate,
            todos: todoEntries,
            memos: cardStore.memoCards(on: selectedDate),
            onToggle: { entry, isDone in
                cardStore.setItemDone(
                    cardId: entry.card.id,
                    itemId: entry.item.id,
                    isDone: isDone
                )
                if isDone {
                    let items = cardStore.todoCards(on: selectedDate).flatMap(\.checklistItems)
                    analytics.todoCompleted(
                        taskCount: items.count,
                        remainingCount: items.filter { !$0.isDone }.count,
                        templateId: settingsStore.settings.template.rawValue,
                        source: "calendar"
                    )
                }
                dashboard.publish()
            },
            onDelete: { cardStore.delete(id: $0) }
        )
    }

    private var todoEntries: [TodoEntry] {
        cardStore.todoCards(on: selectedDate).flatMap { card in
            card.checklistItems.map { TodoEntry(card: card, item: $0) }
        }
    }
}

private struct MonthGrid: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date

    @EnvironmentObject private var cardStore: CardStore
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            header

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let todoItems = cardStore.todoCards(on: date).flatMap(\.checklistItems)
                        let memoCount = cardStore.memoCards(on: date).count
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            pendingTodoCount: todoItems.filter { !$0.isDone }.count,
                            completedTodoCount: todoItems.filter(\.isDone).count,
                            memoCount: memoCount
                        ) {
                            selectedDate = date
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    shiftMonth(by: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(appString(localized: "calendar.previousMonth", defaultValue: "Previous month"))

            Spacer()
            Button {
                let today = Date()
                selectedDate = today
                withMonthAnimation { visibleMonth = today }
            } label: {
                VStack(spacing: 1) {
                    Text(monthTitle)
                        .font(.headline)
                    Text(appString(localized: "calendar.today", defaultValue: "Today"))
                        .font(.caption2)
                }
                .foregroundStyle(palette.textPrimary)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(appString(localized: "calendar.nextMonth", defaultValue: "Next month"))
        }
        .foregroundStyle(palette.accent)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return [] }
        return symbols
    }

    /// Leading nils pad the grid to the correct starting weekday.
    private var days: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let range = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = firstWeekday - 1
        let dates = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + dates
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withMonthAnimation { visibleMonth = shifted }
    }

    private func withMonthAnimation(_ changes: () -> Void) {
        if reduceMotion { changes() } else { withAnimation(.snappy(duration: 0.28), changes) }
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let pendingTodoCount: Int
    let completedTodoCount: Int
    let memoCount: Int
    let onTap: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(foreground)
                HStack(spacing: 3) {
                    if pendingTodoCount + completedTodoCount > 0 {
                        Circle()
                            .fill(pendingTodoCount > 0 ? palette.accent : palette.success)
                            .frame(width: 5, height: 5)
                    }
                    if memoCount > 0 {
                        Circle()
                            .fill(palette.textTertiary)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .regular ? 58 : 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? palette.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday && !isSelected ? palette.accent : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        if isSelected { return palette.onPrimary }
        return palette.textPrimary
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        let base = formatter.string(from: date)
        guard pendingTodoCount + completedTodoCount + memoCount > 0 else { return base }
        return String(
            format: appString(
                localized: "calendar.accessibilitySummary",
                defaultValue: "%@, %d todos, %d completed, %d memos"
            ),
            base,
            pendingTodoCount,
            completedTodoCount,
            memoCount
        )
    }
}

private struct SelectedDayList: View {
    let date: Date
    let todos: [TodoEntry]
    let memos: [Card]
    let onToggle: (TodoEntry, Bool) -> Void
    let onDelete: (String) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            QuickCaptureView(date: date, source: "calendar")

            if todos.isEmpty && memos.isEmpty {
                Text(appString(localized: "calendar.emptyDay", defaultValue: "Nothing on this day"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.vertical, 18)
            } else {
                ForEach(todos, id: \.compositeId) { entry in
                    Button {
                        onToggle(entry, !entry.item.isDone)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(entry.item.isDone ? palette.success : palette.textTertiary)
                            Text(entry.item.text)
                                .foregroundStyle(entry.item.isDone ? palette.textTertiary : palette.textPrimary)
                                .strikethrough(entry.item.isDone)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(memos) { memo in
                    HStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .foregroundStyle(palette.textTertiary)
                        Text(memo.title)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: date)
    }

    private var summary: String {
        String(
            format: appString(localized: "calendar.itemSummary", defaultValue: "%d todos · %d memos"),
            todos.count,
            memos.count
        )
    }
}
