import Combine
import Foundation
import LockTodoNoteShared

/// Observable owner of every card. Views read `cards`; all mutation goes
/// through here so the Lock Screen is refreshed from exactly one place.
@MainActor
final class CardStore: ObservableObject {
    @Published private(set) var cards: [Card] = []
    /// Set when the card file could not be read or written. A silent failure
    /// here looks exactly like data loss to the user, so it is surfaced.
    @Published private(set) var storeError: StoreError?

    enum StoreError: Equatable {
        case readFailed(String)
        case writeFailed(String)

        var isWriteFailure: Bool {
            if case .writeFailed = self { return true }
            return false
        }

        var detail: String {
            switch self {
            case .readFailed(let detail), .writeFailed(let detail): detail
            }
        }
    }

    private let repository: CardRepository
    private let calendar: Calendar

    /// Called after any change lands, so the Live Activity and widget can be
    /// re-published. Set by the app on launch.
    var canConfigureAdvancedRepeat: (@MainActor () -> Bool) = { false }

    var onChange: (@MainActor () -> Void)?

    init(repository: CardRepository = CardRepository(), calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    // MARK: - Loading

    @discardableResult
    func load(now: Date = Date()) -> CardRepository.LoadResult? {
        do {
            let result = try repository.load(now: now)
            cards = result.cards
            storeError = nil
            return result
        } catch {
            // Keep whatever is already on screen rather than blanking the app.
            storeError = .readFailed(String(describing: error))
            return nil
        }
    }

    // MARK: - Queries

    func card(id: String) -> Card? {
        cards.first { $0.id == id }
    }

    func cards(on date: Date) -> [Card] {
        let key = FlutterDate.dateKey(date, calendar: calendar)
        return cards.filter { $0.dayKey(calendar: calendar) == key }
    }

    func todoCards(on date: Date) -> [Card] {
        cards(on: date).filter { $0.type == .checklist }
    }

    func calendarTodoCards(on date: Date) -> [Card] {
        CardMutations.calendarTodos(cards, on: date, calendar: calendar)
    }

    /// Recompute from current storage rather than trusting a stale view snapshot.
    @discardableResult
    func materializeCalendarTodo(id: String, on date: Date) -> Bool {
        if card(id: id) != nil { return true }
        guard let occurrence = calendarTodoCards(on: date).first(where: { $0.id == id }) else { return false }
        return commit(cards + [occurrence])
    }

    func memoCards(on date: Date) -> [Card] {
        cards(on: date).filter { $0.type == .quickNote }
    }

    var pinnedMemo: Card? {
        cards.first { $0.type == .quickNote && $0.isPinned && $0.showOnLockScreen }
    }

    /// Day keys that have any content — drives the calendar's dots.
    func daysWithContent() -> Set<String> {
        var keys: Set<String> = []
        for card in cards {
            let hasContent = card.type == .checklist
                ? !card.checklistItems.isEmpty
                : !card.title.isEmpty || !card.body.isEmpty
            if hasContent { keys.insert(card.dayKey(calendar: calendar)) }
        }
        return keys
    }

    // MARK: - Mutations

    @discardableResult
    func upsert(_ card: Card) -> Bool {
        // The original reminder owns its title, date and recurrence.
        guard AppleReminderMirror.reminderID(from: card.id) == nil else { return false }
        let previous = cards.first { $0.id == card.id }
        for item in card.checklistItems where item.advancedRepeat != nil {
            let old = previous?.checklistItems.first { $0.id == item.id }
            guard item.advancedRepeat?.isValid == true,
                  old?.advancedRepeat == item.advancedRepeat || canConfigureAdvancedRepeat() else { return false }
        }
        var updated = cards
        // A series must share its rule, including when recurrence is turned off.
        for item in card.checklistItems {
            guard let old = previous?.checklistItems.first(where: { $0.id == item.id }),
                  old.recurrence != item.recurrence || old.advancedRepeat != item.advancedRepeat else { continue }
            for cardIndex in updated.indices {
                for index in updated[cardIndex].checklistItems.indices
                where updated[cardIndex].checklistItems[index].effectiveRecurrenceId == old.effectiveRecurrenceId {
                    updated[cardIndex].checklistItems[index].recurrence = item.recurrence
                    updated[cardIndex].checklistItems[index].advancedRepeat = item.advancedRepeat
                    updated[cardIndex].checklistItems[index].recurrenceAnchorDate = item.recurrenceAnchorDate
                }
            }
        }
        // Pinning a memo unpins whatever held the slot before.
        if card.isPinned {
            for index in updated.indices where updated[index].id != card.id {
                updated[index].isPinned = false
                updated[index].showOnLockScreen = false
            }
        }
        if let index = updated.firstIndex(where: { $0.id == card.id }) {
            updated[index] = card
        } else {
            updated.append(card)
        }
        return commit(updated)
    }

    @discardableResult
    func delete(id: String) -> Bool {
        guard AppleReminderMirror.reminderID(from: id) == nil else { return false }
        return commit(cards.filter { $0.id != id })
    }

    @discardableResult
    func setPinnedMemo(_ card: Card?) -> Bool {
        var updated = cards
        for index in updated.indices {
            let isSelected = updated[index].id == card?.id
            updated[index].isPinned = isSelected
            updated[index].showOnLockScreen = isSelected
            if isSelected { updated[index].updatedAt = Date() }
        }
        if let card, !updated.contains(where: { $0.id == card.id }) {
            var pinned = card
            pinned.isPinned = true
            pinned.showOnLockScreen = true
            pinned.updatedAt = Date()
            updated.append(pinned)
        }
        return commit(updated)
    }

    /// Toggles one todo. `itemId` is the item's own id, not the composite.
    func setItemDone(cardId: String, itemId: String, isDone: Bool, source: String = "app") -> Bool {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardId }) else { return false }
        var updated = cards
        guard let itemIndex = updated[cardIndex].checklistItems.firstIndex(where: { $0.id == itemId })
        else { return false }

        let item = updated[cardIndex].checklistItems[itemIndex]
        if let identifier = AppleReminderMirror.reminderID(from: cardId) {
            do {
                try AppleRemindersClient.setCompleted(
                    identifier: identifier, isCompleted: isDone, store: repository.store
                )
            } catch {
                storeError = .writeFailed(error.localizedDescription)
                return false
            }
        }
        updated[cardIndex].checklistItems[itemIndex] = isDone
            ? item.markingDone(at: Date(), source: source, calendar: calendar)
            : item.clearingCompletion()
        updated[cardIndex].updatedAt = Date()
        return commit(updated)
    }

    @discardableResult
    func addTodo(text: String, to date: Date, recurrence: TodoRecurrence = .none) -> Bool {
        addTodos(texts: [text], to: date, recurrence: recurrence)
    }

    /// Adds a pasted multi-line list in one commit so storage, WidgetKit, and
    /// ActivityKit refresh only once.
    @discardableResult
    func addTodos(
        texts: [String], to date: Date, recurrence: TodoRecurrence = .none,
        smartEnabled: Bool = true, recurrenceOverride: TodoRecurrence? = nil,
        advancedRepeat: AdvancedRepeatRule? = nil
    ) -> Bool {
        if let advancedRepeat {
            guard advancedRepeat.isValid, canConfigureAdvancedRepeat() else { return false }
        }
        let values = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return false }

        let now = Date()
        var updated = cards
        let todos = SmartQuickAddParser.parse(
            values.joined(separator: "\n"), referenceDate: now, defaultDate: date,
            recurrenceOverride: recurrenceOverride ?? (recurrence == .none ? nil : recurrence),
            enabled: smartEnabled, calendar: calendar
        )
        guard !todos.isEmpty else { return false }
        for (index, todo) in todos.enumerated() {
            let id = "\(Self.newIdentifier())-\(index)"
            var card = todo.card(id: id, createdAt: now)
            if let advancedRepeat {
                guard let first = advancedRepeat.firstOccurrence(onOrAfter: todo.scheduledDate, calendar: calendar)
                else { return false }
                card.targetDateTime = first
                card.checklistItems[0].recurrence = .none
                card.checklistItems[0].advancedRepeat = advancedRepeat
                card.checklistItems[0].recurrenceAnchorDate = first
                if let dueDate = card.checklistItems[0].dueDate {
                    card.checklistItems[0].dueDate = CardMutations.combine(day: first, time: dueDate, calendar: calendar)
                }
            }
            updated.append(card)
        }
        return commit(updated)
    }

    @discardableResult
    func addMemo(text: String, to date: Date, pinned: Bool = true) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let now = Date()
        let card = Card(
            id: Self.newIdentifier(),
            title: CardMutations.memoTitle(from: trimmed),
            body: trimmed,
            type: .quickNote,
            isPinned: pinned,
            showOnLockScreen: pinned,
            targetDateTime: CardMutations.combine(day: date, time: now, calendar: calendar),
            createdAt: now,
            updatedAt: now
        )
        return upsert(card)
    }

    @discardableResult
    func replaceReminderCopies(with records: [AppleReminderRecord]) -> Bool {
        // A failed read must never be replaced with only the imported items.
        if case .readFailed? = storeError { return false }
        let updated = AppleReminderMirror.reconcile(records, with: cards, calendar: calendar)
        if updated == cards { return true }
        return commit(updated)
    }

    private func commit(_ updated: [Card]) -> Bool {
        let sorted = CardMutations.sorted(updated)
        do {
            try repository.save(sorted)
            cards = sorted
            storeError = nil
        } catch {
            storeError = .writeFailed(String(describing: error))
            return false
        }
        onChange?()
        return true
    }

    /// Matches the Flutter id scheme (microseconds since epoch), which the
    /// rollover and recurrence id formats build on.
    static func newIdentifier() -> String {
        String(Int(Date().timeIntervalSince1970 * 1_000_000))
    }
}
