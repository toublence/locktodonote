import SwiftUI
import LockTodoNoteShared

/// Month grid plus the selected day's contents — the same split the Live
/// Activity's calendar template shows, so the two stay legible together.
struct CalendarTabView: View {
    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.palette) private var palette

    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: horizontalSizeClass == .regular ? 24 : 20) {
                MonthGrid(
                    visibleMonth: $visibleMonth,
                    selectedDate: $selectedDate,
                    markedDayKeys: cardStore.daysWithContent()
                )

                selectedDayList
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
            .padding(.bottom, horizontalSizeClass == .regular ? 36 : 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .onChange(of: selectedDate) { date in
            dashboard.selectedDate = date
            dashboard.publish()
        }
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
            },
            onDelete: { cardStore.delete(id: $0) },
            onAddTodo: { environment.requestQuickAdd(.todo, date: selectedDate, source: "calendar") },
            onAddMemo: { environment.requestQuickAdd(.memo, date: selectedDate, source: "calendar") }
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
    let markedDayKeys: Set<String>

    @Environment(\.palette) private var palette
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
                ForEach(days, id: \.self) { date in
                    if let date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasItems: markedDayKeys.contains(FlutterDate.dateKey(date, calendar: calendar))
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
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
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
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
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
        visibleMonth = shifted
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool
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
                Circle()
                    .fill(hasItems ? palette.accent : .clear)
                    .frame(width: 4, height: 4)
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
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        let base = formatter.string(from: date)
        guard hasItems else { return base }
        return "\(base), \(appString(localized: "calendar.hasItems", defaultValue: "has items"))"
    }
}

private struct SelectedDayList: View {
    let date: Date
    let todos: [TodoEntry]
    let memos: [Card]
    let onToggle: (TodoEntry, Bool) -> Void
    let onDelete: (String) -> Void
    let onAddTodo: () -> Void
    let onAddMemo: () -> Void

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
                Spacer(minLength: 8)
                Menu {
                    Button(action: onAddTodo) {
                        Label(
                            appString(localized: "home.addTodo", defaultValue: "Add todo"),
                            systemImage: "checklist"
                        )
                    }
                    Button(action: onAddMemo) {
                        Label(
                            appString(localized: "home.addMemo", defaultValue: "Add memo"),
                            systemImage: "square.and.pencil"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(palette.accentSoft, in: Circle())
                }
                .accessibilityLabel(appString(localized: "calendar.addItem", defaultValue: "Add item"))
            }

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
        formatter.locale = .current
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
