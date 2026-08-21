import Foundation
import Testing

@testable import LockTodoNoteShared

@Suite("Dashboard composition")
struct DashboardComposerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private var strings: DashboardStrings {
        DashboardStrings(
            noEvents: "No events",
            hiddenContent: "Hidden",
            checkInApp: "Open the app",
            dDayToday: "D-Day",
            dPlusPrefix: "D+",
            timePassed: "Passed",
            hoursMinutesRemaining: "left",
            remainingTasks: "Remaining"
        )
    }

    private var composer: DashboardComposer {
        DashboardComposer(strings: strings, calendar: calendar, localeIdentifier: "en_US")
    }

    private func day(_ key: String) -> Date {
        FlutterDate.date(fromKey: key, calendar: calendar)!
    }

    private func todoCard(id: String, day dayKey: String, items: [ChecklistItem]) -> Card {
        let date = day(dayKey)
        return Card(
            id: id,
            title: items.first?.text ?? "",
            type: .checklist,
            checklistItems: items,
            targetDateTime: date,
            createdAt: date,
            updatedAt: date
        )
    }

    private func memoCard(id: String, day dayKey: String, title: String, body: String, pinned: Bool = false) -> Card {
        let date = day(dayKey)
        return Card(
            id: id,
            title: title,
            body: body,
            type: .quickNote,
            isPinned: pinned,
            showOnLockScreen: pinned,
            targetDateTime: date,
            createdAt: date,
            updatedAt: date
        )
    }

    // MARK: - Selection

    @Test func showsOnlyTheSelectedDaysItems() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [ChecklistItem(id: "1", text: "Today")]),
            todoCard(id: "b", day: "2026-08-22", items: [ChecklistItem(id: "2", text: "Tomorrow")]),
        ]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        #expect(snapshot.todoItems.map(\.text) == ["Today"])
        #expect(snapshot.totalCount == 1)
    }

    @Test func countsReflectCompletionOnTheSelectedDay() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [
                ChecklistItem(id: "1", text: "Done", isDone: true),
                ChecklistItem(id: "2", text: "Not done"),
            ])
        ]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        #expect(snapshot.totalCount == 2)
        #expect(snapshot.doneCount == 1)
        #expect(snapshot.remainingCount == 1)
    }

    @Test func hidingCompletedTodosRemovesThemFromTheCard() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [
                ChecklistItem(id: "1", text: "Done", isDone: true),
                ChecklistItem(id: "2", text: "Not done"),
            ])
        ]
        var settings = LockScreenSettings()
        settings.showCompletedTodos = false
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: settings,
            now: day("2026-08-21")
        )
        #expect(snapshot.todoItems.map(\.text) == ["Not done"])
        // The counts still describe reality, not the filtered view.
        #expect(snapshot.totalCount == 2)
        #expect(snapshot.doneCount == 1)
    }

    @Test func togglesHideTodosAndMemosIndependently() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [ChecklistItem(id: "1", text: "Todo")]),
            memoCard(id: "m", day: "2026-08-21", title: "Memo", body: "Body"),
        ]
        var settings = LockScreenSettings()
        settings.showTodos = false
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: settings,
            now: day("2026-08-21")
        )
        #expect(snapshot.todoItems.isEmpty)
        #expect(!snapshot.memoItems.isEmpty)
        #expect(!snapshot.showTodosOnLockScreen)
    }

    // MARK: - Privacy

    @Test func hiddenPrivacyModeRedactsEveryItem() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [ChecklistItem(id: "1", text: "Secret todo")]),
            memoCard(id: "m", day: "2026-08-21", title: "Secret memo", body: "Body"),
        ]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            privacyMode: .hidden,
            now: day("2026-08-21")
        )
        #expect(snapshot.todoItems.allSatisfy { $0.text == "Hidden" })
        #expect(snapshot.memoItems.allSatisfy { $0.title == "Hidden" })
        #expect(snapshot.todoItems.count == 1, "redaction hides content, not the fact that items exist")
    }

    // MARK: - D-Day

    @Test(arguments: [
        ("2026-08-25", "D-4"),
        ("2026-08-22", "D-1"),
        ("2026-08-21", "D-Day"),
        ("2026-08-20", "D+1"),
        ("2026-08-14", "D+7"),
    ])
    func computesDdayRelativeToToday(target: String, expected: String) {
        let text = composer.ddayText(day(target), now: day("2026-08-21"))
        #expect(text == expected)
    }

    @Test func ddayIgnoresTimeOfDay() {
        // Late-evening "today" must still read D-Day, not D+1.
        let target = FlutterDate.parse("2026-08-21T00:30:00.000000")!
        let now = FlutterDate.parse("2026-08-21T23:45:00.000000")!
        #expect(composer.ddayText(target, now: now) == "D-Day")
    }

    @Test func ddaySettingsFlowIntoTheSnapshot() {
        var settings = LockScreenSettings()
        settings.template = .ddayMemo
        settings.ddayTitle = "Trip"
        settings.ddayMemo = "Pack the passport"
        settings.ddayTargetDate = day("2026-08-25")

        let snapshot = composer.compose(
            cards: [],
            selectedDate: day("2026-08-21"),
            settings: settings,
            now: day("2026-08-21")
        )
        #expect(snapshot.ddayTitle == "Trip")
        #expect(snapshot.ddayText == "D-4")
        #expect(snapshot.ddayMemo == "Pack the passport")
        #expect(snapshot.lockScreenLayout == "ddayMemo")
    }

    // MARK: - Calendar grid

    @Test func buildsWholeWeeksForTheSelectedMonth() {
        let snapshot = composer.compose(
            cards: [],
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        #expect(snapshot.calendarDays.count % 7 == 0)
        #expect(snapshot.calendarDays.contains { $0.id == "2026-08-21" && $0.isSelected })
        #expect(snapshot.calendarDays.filter(\.isSelected).count == 1)
    }

    @Test func calendarGridAlwaysStartsOnSunday() {
        let snapshot = composer.compose(
            cards: [],
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )

        #expect(snapshot.calendarDays.first?.id == "2026-07-26")
        let selectedIndex = snapshot.calendarDays.firstIndex { $0.id == "2026-08-21" }
        #expect(selectedIndex.map { $0 % 7 } == 5)
    }

    @Test func marksDaysThatHaveContent() {
        let cards = [todoCard(id: "a", day: "2026-08-05", items: [ChecklistItem(id: "1", text: "Item")])]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        let marked = snapshot.calendarDays.filter(\.hasItems).map(\.id)
        #expect(marked.contains("2026-08-05"))
    }

    @Test func preComposesTomorrowSoTheWidgetCanRollOverAtMidnight() {
        let snapshot = composer.compose(
            cards: [],
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        #expect(snapshot.preparedNextDay?.id == "2026-08-22")
    }

    @Test func projectsUnfinishedWorkOntoTomorrow() {
        let cards = [
            todoCard(id: "a", day: "2026-08-20", items: [ChecklistItem(id: "1", text: "Carry over")])
        ]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        let tomorrow = snapshot.calendarDays.first { $0.id == "2026-08-22" }
        #expect(tomorrow?.todoItems.map(\.text).contains("Carry over") == true)
    }

    // MARK: - Payload size

    @Test func capsTodosAndTruncatesLongText() {
        let long = String(repeating: "very long todo text ", count: 10)
        let items = (0..<12).map { ChecklistItem(id: "\($0)", text: "\(long)\($0)") }
        let snapshot = composer.compose(
            cards: [todoCard(id: "a", day: "2026-08-21", items: items)],
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        // ActivityKit payloads are tiny; both limits protect that budget.
        #expect(snapshot.todoItems.count == 5)
        #expect(snapshot.todoItems.allSatisfy { $0.text.count <= 28 })
        #expect(snapshot.todoItems.allSatisfy { $0.text.hasSuffix("…") })
    }

    // MARK: - Wire format

    @Test func snapshotSurvivesTheAppGroupRoundTrip() {
        let cards = [
            todoCard(id: "a", day: "2026-08-21", items: [ChecklistItem(id: "1", text: "Todo")]),
            memoCard(id: "m", day: "2026-08-21", title: "Memo", body: "Body", pinned: true),
        ]
        var settings = LockScreenSettings()
        settings.template = .memoTodo
        settings.textScale = 1.2

        let original = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: settings,
            now: day("2026-08-21")
        )
        let restored = DashboardSnapshot(dictionary: original.dictionary(isPro: true))

        #expect(restored.todoItems == original.todoItems)
        #expect(restored.memoItems == original.memoItems)
        #expect(restored.lockScreenLayout == "memoTodo")
        #expect(restored.textScale == 1.2)
        #expect(restored.totalCount == original.totalCount)
        #expect(restored.calendarDays.count == original.calendarDays.count)
    }

    @Test func liveActivityStateDropsTheGridButKeepsMarkedDays() {
        let cards = [todoCard(id: "a", day: "2026-08-05", items: [ChecklistItem(id: "1", text: "Item")])]
        let snapshot = composer.compose(
            cards: cards,
            selectedDate: day("2026-08-21"),
            settings: LockScreenSettings(),
            now: day("2026-08-21")
        )
        // `GlanceDashboardAttributes.ContentState` is a typealias for this on iOS.
        let state = DashboardActivityState(snapshot: snapshot)
        #expect(state.calendarDays.isEmpty, "the full grid never goes over the wire")
        #expect(state.itemDateIds.contains("2026-08-05"))
    }
}

@Suite("Shortcut target resolution")
struct ShortcutTargetTests {
    private func settings(
        template: LockScreenTemplate,
        priority: ShortcutInsertPriority = .todo
    ) -> LockScreenSettings {
        var settings = LockScreenSettings()
        settings.template = template
        settings.shortcutInsertPriority = priority
        return settings
    }

    @Test(arguments: [
        LockScreenTemplate.dateMemo, .imageMemo, .ddayMemo,
    ])
    func memoOnlyTemplatesAlwaysStoreMemos(_ template: LockScreenTemplate) {
        #expect(settings(template: template, priority: .todo).resolveShortcutTarget() == .memo)
    }

    @Test(arguments: [LockScreenTemplate.dateTodo, .imageTodo])
    func todoOnlyTemplatesAlwaysStoreTodos(_ template: LockScreenTemplate) {
        #expect(settings(template: template, priority: .memo).resolveShortcutTarget() == .todo)
    }

    @Test(arguments: [LockScreenTemplate.calendarItems, .memoTodo])
    func mixedTemplatesFollowThePreference(_ template: LockScreenTemplate) {
        #expect(settings(template: template, priority: .memo).resolveShortcutTarget() == .memo)
        #expect(settings(template: template, priority: .todo).resolveShortcutTarget() == .todo)
    }

    /// Layouts the renderer knows but the picker never offers fold back to the
    /// default rather than resolving to something unexpected.
    @Test(arguments: ["ddayTodo", "imageDday", "nonsense"])
    func unknownLayoutsFallBackToTheDefault(_ raw: String) {
        #expect(LockScreenTemplate(fromStored: raw) == .calendarItems)
    }
}

@Suite("Entitlement rules")
struct EntitlementTests {
    @Test func lifetimeOutranksSubscriptions() {
        #expect(ProductIdentifiers.priority(ProductIdentifiers.lifetime) > ProductIdentifiers.priority(ProductIdentifiers.yearlyLegacy))
        #expect(ProductIdentifiers.priority(ProductIdentifiers.yearlyLegacy) > ProductIdentifiers.priority(ProductIdentifiers.monthly))
    }

    /// The shipped typo and the corrected spelling must both be recognised.
    @Test func bothYearlySpellingsCount() {
        #expect(ProductIdentifiers.isYearly("com.namslab.glancecard.yealy"))
        #expect(ProductIdentifiers.isYearly("com.namslab.glancecard.yearly"))
        #expect(ProductIdentifiers.isSupported("com.namslab.glancecard.yealy"))
    }

    @Test func rejectsUnknownProducts() {
        #expect(!ProductIdentifiers.isSupported("com.someoneelse.pro"))
        #expect(ProductIdentifiers.Kind(productId: "com.someoneelse.pro") == nil)
    }

    @Test func cachedEntitlementRoundTrips() throws {
        let original = Entitlement(
            isPro: true,
            productId: ProductIdentifiers.yearlyLegacy,
            purchasedAt: Date(),
            expirationDate: Date().addingTimeInterval(86_400),
            source: "storekit2_verified"
        )
        let restored = Entitlement(cachedJSON: original.cachedJSON)
        #expect(restored.isPro)
        #expect(restored.productId == ProductIdentifiers.yearlyLegacy)
        #expect(restored.kind == .yearly)
    }

    @Test func expiredCacheIsNotPro() throws {
        let expired = Entitlement(
            isPro: true,
            productId: ProductIdentifiers.monthly,
            purchasedAt: Date().addingTimeInterval(-86_400 * 40),
            expirationDate: Date().addingTimeInterval(-86_400),
            source: "storekit2_verified"
        )
        let restored = Entitlement(cachedJSON: expired.cachedJSON)
        #expect(!restored.isPro, "an expired cache must not keep Pro alive")
    }

    @Test func lifetimeCacheHasNoExpiry() throws {
        let lifetime = Entitlement(
            isPro: true,
            productId: ProductIdentifiers.lifetime,
            purchasedAt: Date(),
            expirationDate: nil,
            source: "storekit2_verified"
        )
        let restored = Entitlement(cachedJSON: lifetime.cachedJSON)
        #expect(restored.isPro)
    }

    @Test func corruptCacheFallsBackToFree() {
        #expect(!Entitlement(cachedJSON: "not json").isPro)
        #expect(!Entitlement(cachedJSON: nil).isPro)
    }

    /// The 24-hour preview opens templates only — never themes or the
    /// unlimited-Shortcuts allowance.
    @Test func temporaryTrialUnlocksTemplatesOnly() {
        var entitlement = Entitlement.none
        entitlement.temporaryTrialActive = true

        #expect(entitlement.canUse(.imageMemoTemplate))
        #expect(entitlement.canUse(.ddayMemoTemplate))
        #expect(!entitlement.canUse(.themes))
        #expect(!entitlement.canUse(.unlimitedShortcuts))
    }

    @Test func proUnlocksEverything() {
        let pro = Entitlement(
            isPro: true,
            productId: ProductIdentifiers.lifetime,
            purchasedAt: nil,
            expirationDate: nil,
            source: "storekit2_verified"
        )
        #expect(ProFeature.allCases.allSatisfy(pro.canUse))
    }

    @Test func freeUnlocksNothing() {
        #expect(ProFeature.allCases.allSatisfy { !Entitlement.none.canUse($0) })
    }
}
