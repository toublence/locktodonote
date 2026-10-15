import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Apple Reminders mirror")
struct AppleReminderMirrorTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func identifiersSurviveCompositeIDs() {
        let identifier = "x-apple-reminder://ABC:123/한글+task"
        let cardID = AppleReminderMirror.cardID(for: identifier)
        #expect(!cardID.contains(":"))
        #expect(AppleReminderMirror.reminderID(from: cardID) == identifier)
        #expect(AppleReminderMirror.reminderID(from: "native-task") == nil)
    }

    @Test func importIsIdempotentAndKeepsNativeCards() {
        let native = Card(id: "native", title: "Local", type: .quickNote, createdAt: now, updatedAt: now)
        let record = AppleReminderRecord(identifier: "remote", title: "Buy milk")
        let first = AppleReminderMirror.reconcile([record, record], with: [native], now: now, calendar: calendar)
        let second = AppleReminderMirror.reconcile([record], with: first, now: now.addingTimeInterval(60), calendar: calendar)
        #expect(first == second)
        #expect(first.count == 2)
        #expect(first.contains(native))
    }

    @Test func remoteTitleCompletionAndUndoReplaceTheMirror() {
        let initial = AppleReminderMirror.reconcile(
            [AppleReminderRecord(identifier: "remote", title: "Original")], with: [], now: now, calendar: calendar
        )
        let completed = AppleReminderMirror.reconcile(
            [AppleReminderRecord(identifier: "remote", title: "Renamed", isCompleted: true, completionDate: now)],
            with: initial, now: now, calendar: calendar
        )
        #expect(completed.first?.title == "Renamed")
        #expect(completed.first?.checklistItems.first?.isDone == true)
        let reopened = AppleReminderMirror.reconcile(
            [AppleReminderRecord(identifier: "remote", title: "Renamed")],
            with: completed, now: now, calendar: calendar
        )
        #expect(reopened.first?.checklistItems.first?.isDone == false)
        #expect(reopened.first?.checklistItems.first?.completedAt == nil)
    }

    @Test func deletedOrDeselectedCopiesDoNotDeleteNativeData() {
        let native = Card(id: "native", title: "Local", type: .quickNote, createdAt: now, updatedAt: now)
        let imported = AppleReminderMirror.reconcile(
            [AppleReminderRecord(identifier: "remote", title: "Remote")], with: [native], now: now, calendar: calendar
        )
        #expect(AppleReminderMirror.reconcile([], with: imported, now: now, calendar: calendar) == [native])
    }

    @Test func overdueAndUndatedAppearTodayAndFutureDatesArePreserved() {
        let future = now.addingTimeInterval(3 * 86_400)
        let records = [
            AppleReminderRecord(identifier: "overdue", title: "Overdue", dueDate: now.addingTimeInterval(-86_400)),
            AppleReminderRecord(identifier: "undated", title: "Undated"),
            AppleReminderRecord(identifier: "future", title: "Future", dueDate: future),
        ]
        let cards = AppleReminderMirror.reconcile(records, with: [], now: now, calendar: calendar)
        let futureCard = cards.first { AppleReminderMirror.reminderID(from: $0.id) == "future" }
        #expect(futureCard?.day(calendar: calendar) == calendar.startOfDay(for: future))
        #expect(cards.filter { $0.day(calendar: calendar) == calendar.startOfDay(for: now) }.count == 2)
        #expect(futureCard?.checklistItems.first?.recurrence == TodoRecurrence.none)
    }

    @Test func completedHistoryIsNotImportedOnFirstConnection() {
        let cards = AppleReminderMirror.reconcile(
            [AppleReminderRecord(identifier: "old", title: "Old completed task", isCompleted: true, completionDate: now)],
            with: [], now: now, calendar: calendar
        )
        #expect(cards.isEmpty)
    }
}
