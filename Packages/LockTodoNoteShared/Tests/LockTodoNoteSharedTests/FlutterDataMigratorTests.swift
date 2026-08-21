import Foundation
import Testing

@testable import LockTodoNoteShared

@Suite("Flutter data migration", .serialized)
final class FlutterDataMigratorTests {
    private let standardSuite: String
    private let groupSuite: String
    private let standardDefaults: UserDefaults
    private let groupDefaults: UserDefaults
    private let directory: URL

    init() throws {
        let unique = UUID().uuidString
        standardSuite = "test.standard.\(unique)"
        groupSuite = "test.group.\(unique)"
        standardDefaults = try #require(UserDefaults(suiteName: standardSuite))
        groupDefaults = try #require(UserDefaults(suiteName: groupSuite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator-\(unique)", isDirectory: true)
    }

    deinit {
        standardDefaults.removePersistentDomain(forName: standardSuite)
        groupDefaults.removePersistentDomain(forName: groupSuite)
        try? FileManager.default.removeItem(at: directory)
    }

    private var cardStoreURL: URL {
        directory.appendingPathComponent("Data").appendingPathComponent("cards.json")
    }

    private func makeMigrator(now: Date = Date()) -> FlutterDataMigrator {
        FlutterDataMigrator(
            standardDefaults: standardDefaults,
            groupDefaults: groupDefaults,
            cardStoreURL: cardStoreURL,
            now: { now }
        )
    }

    private func seedFlutterCards(_ json: String) {
        standardDefaults.set(
            json,
            forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.cards)
        )
    }

    private func migratedCards() throws -> [Card] {
        let data = try Data(contentsOf: cardStoreURL)
        return try JSONDecoder().decode([Card].self, from: data)
    }

    // MARK: - Happy path

    @Test func migratesCardsFromPrefixedKey() throws {
        seedFlutterCards("[\(DartFixtures.checklistCard),\(DartFixtures.memoCard)]")

        let outcome = makeMigrator().migrateIfNeeded()

        #expect(outcome == .migrated(cardCount: 2))
        let cards = try migratedCards()
        #expect(cards.count == 2)
        #expect(Set(cards.map(\.id)) == ["1755000000000000", "1755000000000001"])
    }

    /// The single most dangerous assumption in the whole migration: Flutter's
    /// shared_preferences prefixes every key with "flutter.".
    @Test func ignoresUnprefixedKeys() throws {
        standardDefaults.set("[\(DartFixtures.checklistCard)]", forKey: FlutterPreferenceKeys.cards)

        let outcome = makeMigrator().migrateIfNeeded()

        #expect(outcome == .nothingToMigrate, "an unprefixed key is not Flutter data")
        #expect(!FileManager.default.fileExists(atPath: cardStoreURL.path))
    }

    @Test func copiesSettingsAndFlags() throws {
        seedFlutterCards("[\(DartFixtures.checklistCard)]")
        standardDefaults.set("imageMemo", forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.layout))
        standardDefaults.set(false, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.showMemos))
        standardDefaults.set(1.25, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.textScale))
        standardDefaults.set(7, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.morningReminderHour))
        standardDefaults.set("chwiram", forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.colorTheme))
        standardDefaults.set(true, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.hasCompletedOnboarding))

        _ = makeMigrator().migrateIfNeeded()

        #expect(groupDefaults.string(forKey: FlutterPreferenceKeys.layout) == "imageMemo")
        #expect(groupDefaults.object(forKey: FlutterPreferenceKeys.showMemos) as? Bool == false)
        #expect(groupDefaults.double(forKey: FlutterPreferenceKeys.textScale) == 1.25)
        #expect(groupDefaults.integer(forKey: FlutterPreferenceKeys.morningReminderHour) == 7)
        #expect(groupDefaults.string(forKey: FlutterPreferenceKeys.colorTheme) == "chwiram")
        #expect(groupDefaults.bool(forKey: FlutterPreferenceKeys.hasCompletedOnboarding))

        let settings = LockScreenSettings.load(from: groupDefaults)
        #expect(settings.template == .imageMemo)
        #expect(!settings.showMemos)
        #expect(settings.textScale == 1.25)
    }

    @Test func preservesOriginalFlutterKeys() throws {
        seedFlutterCards("[\(DartFixtures.checklistCard)]")
        standardDefaults.set(true, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.hasCompletedOnboarding))

        _ = makeMigrator().migrateIfNeeded()

        // Rolling back to the Flutter build has to remain possible.
        #expect(
            standardDefaults.string(forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.cards)) != nil
        )
        #expect(
            standardDefaults.bool(forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.hasCompletedOnboarding))
        )
    }

    // MARK: - Idempotence

    @Test func runsOnlyOnce() throws {
        seedFlutterCards("[\(DartFixtures.checklistCard)]")

        #expect(makeMigrator().migrateIfNeeded() == .migrated(cardCount: 1))
        #expect(makeMigrator().migrateIfNeeded() == .alreadyMigrated)
    }

    @Test func doesNotOverwriteLaterEditsOnSecondLaunch() throws {
        seedFlutterCards("[\(DartFixtures.checklistCard)]")
        _ = makeMigrator().migrateIfNeeded()

        // Simulate the user deleting everything inside the SwiftUI app.
        try Data("[]".utf8).write(to: cardStoreURL)
        _ = makeMigrator().migrateIfNeeded()

        #expect(try migratedCards().isEmpty, "a second run must not resurrect old cards")
    }

    // MARK: - Failure handling

    @Test func failsWithoutCommittingVersionWhenJSONIsCorrupt() throws {
        seedFlutterCards("{ this is not valid json")

        let outcome = makeMigrator().migrateIfNeeded()

        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(groupDefaults.integer(forKey: AppGroupKeys.migrationVersion) == 0, "retry on next launch")
        #expect(groupDefaults.string(forKey: AppGroupKeys.migrationFailureReason) != nil)
    }

    @Test func retrySucceedsAfterTransientFailure() throws {
        seedFlutterCards("{ corrupt")
        _ = makeMigrator().migrateIfNeeded()

        seedFlutterCards("[\(DartFixtures.checklistCard)]")
        #expect(makeMigrator().migrateIfNeeded() == .migrated(cardCount: 1))
        #expect(groupDefaults.string(forKey: AppGroupKeys.migrationFailureReason) == nil)
    }

    @Test func failsWhenACardCannotBeCounted() throws {
        // A JSON object where an array is expected.
        seedFlutterCards("{\"cards\": []}")
        guard case .failed = makeMigrator().migrateIfNeeded() else {
            Issue.record("expected failure for non-array payload")
            return
        }
    }

    // MARK: - Fresh installs

    @Test func stampsVersionForAFreshInstall() throws {
        #expect(makeMigrator().migrateIfNeeded() == .nothingToMigrate)
        #expect(groupDefaults.integer(forKey: AppGroupKeys.migrationVersion) == FlutterDataMigrator.currentVersion)
    }

    @Test func migratesOnboardingOnlyInstallWithNoCards() throws {
        standardDefaults.set(true, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.hasCompletedOnboarding))
        #expect(makeMigrator().migrateIfNeeded() == .migrated(cardCount: 0))
        #expect(groupDefaults.bool(forKey: FlutterPreferenceKeys.hasCompletedOnboarding))
    }

    // MARK: - Seed template cleanup

    @Test func dropsAbandonedKoreanSeedTemplates() throws {
        let seedCard = """
        {
          "id": "seed-1",
          "title": "장보기",
          "body": "우유\\n계란\\n물\\n과일",
          "type": "checklist",
          "privacyMode": "full",
          "checklistItems": [
            {"id": "a", "text": "우유", "isDone": false, "recurrence": "none"},
            {"id": "b", "text": "계란", "isDone": false, "recurrence": "none"},
            {"id": "c", "text": "물", "isDone": false, "recurrence": "none"},
            {"id": "d", "text": "과일", "isDone": false, "recurrence": "none"}
          ],
          "isPinned": false,
          "showOnLockScreen": false,
          "targetDateTime": null,
          "createdAt": "2026-08-01T09:00:00.000000",
          "updatedAt": "2026-08-01T09:00:00.000000",
          "lastActivatedAt": null
        }
        """
        seedFlutterCards("[\(seedCard),\(DartFixtures.checklistCard)]")

        #expect(makeMigrator().migrateIfNeeded() == .migrated(cardCount: 1))
        let cards = try migratedCards()
        #expect(cards.map(\.id) == ["1755000000000000"])
    }

    @Test func keepsAUserEditedCardThatMerelyLooksLikeASeed() throws {
        // Same title, different items — the user made it their own.
        let edited = """
        {
          "id": "mine",
          "title": "장보기",
          "body": "우유\\n계란",
          "type": "checklist",
          "privacyMode": "full",
          "checklistItems": [
            {"id": "a", "text": "우유", "isDone": false, "recurrence": "none"},
            {"id": "b", "text": "계란", "isDone": false, "recurrence": "none"}
          ],
          "isPinned": false,
          "showOnLockScreen": false,
          "targetDateTime": null,
          "createdAt": "2026-08-01T09:00:00.000000",
          "updatedAt": "2026-08-01T09:00:00.000000",
          "lastActivatedAt": null
        }
        """
        seedFlutterCards("[\(edited)]")
        #expect(makeMigrator().migrateIfNeeded() == .migrated(cardCount: 1))
    }

    // MARK: - Shortcut counter

    /// The Flutter build counted Shortcut adds twice — once in the App Group
    /// from the intent, once in standard defaults from the app — so the free
    /// limit could be exceeded. The migration folds them into one counter.
    @Test func foldsTheTwoShortcutCountersKeepingTheHigher() throws {
        let now = FlutterDate.parse("2026-08-21T12:00:00.000000")!
        let today = FlutterDate.dateKey(now)
        seedFlutterCards("[]")
        standardDefaults.set(today, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageDate))
        standardDefaults.set(4, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageCount))
        groupDefaults.set(today, forKey: AppGroupKeys.shortcutUsageDate)
        groupDefaults.set(2, forKey: AppGroupKeys.shortcutUsageCount)

        _ = makeMigrator(now: now).migrateIfNeeded()

        #expect(groupDefaults.integer(forKey: AppGroupKeys.shortcutUsageCount) == 4)
        #expect(groupDefaults.string(forKey: AppGroupKeys.shortcutUsageDate) == today)
    }

    @Test func ignoresAStaleShortcutCounterFromAnEarlierDay() throws {
        let now = FlutterDate.parse("2026-08-21T12:00:00.000000")!
        seedFlutterCards("[]")
        standardDefaults.set("2026-08-20", forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageDate))
        standardDefaults.set(5, forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageCount))

        _ = makeMigrator(now: now).migrateIfNeeded()

        #expect(groupDefaults.integer(forKey: AppGroupKeys.shortcutUsageCount) == 0, "yesterday's usage does not carry")
    }
}
