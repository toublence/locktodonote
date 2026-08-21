import Foundation

/// Copies the Flutter build's data into the SwiftUI stores exactly once.
///
/// Three rules make a rollback to the Flutter build possible at any point:
/// the original `flutter.*` keys are only ever read, the migration version is
/// committed only after the copy verifies, and a failure leaves the version
/// untouched so the next launch retries instead of half-migrating.
/// Not `Sendable`: it holds `UserDefaults` and runs synchronously on the main
/// actor during launch, before any concurrent work starts.
public struct FlutterDataMigrator {
    public static let currentVersion = 1

    private let standardDefaults: UserDefaults
    private let groupDefaults: UserDefaults
    private let cardStoreURL: URL?
    private let now: () -> Date

    public init?(
        standardDefaults: UserDefaults = .standard,
        store: AppGroupStore = AppGroupStore(),
        now: @escaping () -> Date = Date.init
    ) {
        guard let groupDefaults = store.defaults else { return nil }
        self.standardDefaults = standardDefaults
        self.groupDefaults = groupDefaults
        self.cardStoreURL = store.cardStoreURL
        self.now = now
    }

    /// Test seam: lets a test drive the migrator without an App Group container.
    public init(
        standardDefaults: UserDefaults,
        groupDefaults: UserDefaults,
        cardStoreURL: URL?,
        now: @escaping () -> Date = Date.init
    ) {
        self.standardDefaults = standardDefaults
        self.groupDefaults = groupDefaults
        self.cardStoreURL = cardStoreURL
        self.now = now
    }

    public enum Outcome: Equatable, Sendable {
        /// Already run — nothing to do.
        case alreadyMigrated
        /// No Flutter install to read; this is a fresh user.
        case nothingToMigrate
        case migrated(cardCount: Int)
        case failed(reason: String)

        public var didWork: Bool {
            switch self {
            case .migrated: true
            case .alreadyMigrated, .nothingToMigrate, .failed: false
            }
        }
    }

    @discardableResult
    public func migrateIfNeeded() -> Outcome {
        guard groupDefaults.integer(forKey: AppGroupKeys.migrationVersion) < Self.currentVersion else {
            return .alreadyMigrated
        }

        let rawCards = standardDefaults.string(
            forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.cards)
        )
        let hasAnyFlutterData = rawCards != nil
            || standardDefaults.object(
                forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.hasCompletedOnboarding)
            ) != nil

        guard hasAnyFlutterData else {
            // A fresh install still stamps the version so a later Flutter-shaped
            // payload cannot be mistaken for un-migrated data.
            commitVersion()
            return .nothingToMigrate
        }

        let cards: [Card]
        do {
            cards = try decodeCards(from: rawCards)
        } catch {
            let reason = "cards_decode_failed: \(error)"
            groupDefaults.set(reason, forKey: AppGroupKeys.migrationFailureReason)
            return .failed(reason: reason)
        }

        let cleaned = removingSeedTemplates(from: cards)
        do {
            try writeCards(cleaned)
        } catch {
            let reason = "cards_write_failed: \(error)"
            groupDefaults.set(reason, forKey: AppGroupKeys.migrationFailureReason)
            return .failed(reason: reason)
        }

        copyPreferences()
        foldShortcutUsageCounter()
        groupDefaults.removeObject(forKey: AppGroupKeys.migrationFailureReason)
        commitVersion()
        return .migrated(cardCount: cleaned.count)
    }

    // MARK: - Cards

    private func decodeCards(from raw: String?) throws -> [Card] {
        guard let raw, !raw.isEmpty else { return [] }
        guard let data = raw.data(using: .utf8) else {
            throw MigrationError.notUTF8
        }
        // Verify against the raw array length so a card that fails to decode is
        // caught here rather than disappearing silently.
        let rawElements = try JSONSerialization.jsonObject(with: data)
        guard let rawArray = rawElements as? [Any] else {
            throw MigrationError.notAnArray
        }
        let cards = try JSONDecoder().decode([Card].self, from: data)
        guard cards.count == rawArray.count else {
            throw MigrationError.cardCountMismatch(expected: rawArray.count, decoded: cards.count)
        }
        return cards
    }

    private func writeCards(_ cards: [Card]) throws {
        guard let cardStoreURL else { throw MigrationError.noAppGroupContainer }
        let directory = cardStoreURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(CardMutations.sorted(cards))
        try data.write(to: cardStoreURL, options: .atomic)
        #if os(iOS)
        // Intents and widgets read this file while the device is locked.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: cardStoreURL.path
        )
        #endif
    }

    /// The Flutter build shipped five Korean starter checklists and later
    /// deleted them on launch. Anyone who never opened that version still has
    /// them, so the cleanup runs once more here.
    private func removingSeedTemplates(from cards: [Card]) -> [Card] {
        cards.filter { !Self.isSeedTemplate($0) }
    }

    static func isSeedTemplate(_ card: Card) -> Bool {
        guard card.type == .checklist, !card.isPinned else { return false }
        guard let seedItems = seedTemplates[card.title] else { return false }
        guard card.body == seedItems.joined(separator: "\n") else { return false }
        return card.checklistItems.map(\.text) == seedItems
    }

    static let seedTemplates: [String: [String]] = [
        "외출 전": ["지갑", "이어폰", "우산", "충전기"],
        "장보기": ["우유", "계란", "물", "과일"],
        "병원 가기 전": ["신분증", "예약 시간 확인", "증상 메모"],
        "공부 목표": ["오늘 할 단원", "문제 풀이", "오답 정리"],
        "여행 전": ["여권", "충전기", "예약 확인", "지갑"],
    ]

    // MARK: - Preferences

    private func copyPreferences() {
        for key in Self.copiedStringKeys {
            if let value = standardDefaults.string(forKey: FlutterPreferenceKeys.prefixed(key)) {
                groupDefaults.set(value, forKey: key)
            }
        }
        for key in Self.copiedBoolKeys {
            if let value = standardDefaults.object(forKey: FlutterPreferenceKeys.prefixed(key)) as? Bool {
                groupDefaults.set(value, forKey: key)
            }
        }
        for key in Self.copiedIntKeys {
            if let value = standardDefaults.object(forKey: FlutterPreferenceKeys.prefixed(key)) as? Int {
                groupDefaults.set(value, forKey: key)
            }
        }
        for key in Self.copiedDoubleKeys {
            if let value = standardDefaults.object(forKey: FlutterPreferenceKeys.prefixed(key)) as? Double {
                groupDefaults.set(value, forKey: key)
            }
        }
    }

    /// The intent counted Shortcut adds in the App Group while the app counted
    /// them in standard defaults. Carry the higher of the two forward for today
    /// so the free limit cannot be reset by the upgrade itself.
    private func foldShortcutUsageCounter() {
        let today = FlutterDate.dateKey(now())
        let appDate = standardDefaults.string(
            forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageDate)
        )
        let appCount = appDate == today
            ? standardDefaults.integer(forKey: FlutterPreferenceKeys.prefixed(FlutterPreferenceKeys.shortcutUsageCount))
            : 0
        let intentCount = groupDefaults.string(forKey: AppGroupKeys.shortcutUsageDate) == today
            ? groupDefaults.integer(forKey: AppGroupKeys.shortcutUsageCount)
            : 0
        let merged = max(appCount, intentCount)
        guard merged > 0 else { return }
        groupDefaults.set(today, forKey: AppGroupKeys.shortcutUsageDate)
        groupDefaults.set(merged, forKey: AppGroupKeys.shortcutUsageCount)
    }

    private func commitVersion() {
        groupDefaults.set(Self.currentVersion, forKey: AppGroupKeys.migrationVersion)
        groupDefaults.set(FlutterDate.utcString(from: now()), forKey: AppGroupKeys.migrationCompletedAt)
    }

    // MARK: - Key inventory

    static let copiedStringKeys: [String] = [
        FlutterPreferenceKeys.activeCardId,
        FlutterPreferenceKeys.defaultPrivacyMode,
        FlutterPreferenceKeys.links,
        FlutterPreferenceKeys.linkCategories,
        FlutterPreferenceKeys.purchaseState,
        FlutterPreferenceKeys.temporaryProTrialExpiresAt,
        FlutterPreferenceKeys.legacyTemporaryProDay,
        FlutterPreferenceKeys.layout,
        FlutterPreferenceKeys.imageFileName,
        FlutterPreferenceKeys.imageMemoFileName,
        FlutterPreferenceKeys.imageTodoFileName,
        FlutterPreferenceKeys.ddayTitle,
        FlutterPreferenceKeys.ddayTargetDate,
        FlutterPreferenceKeys.ddayMemo,
        FlutterPreferenceKeys.textFontWeight,
        FlutterPreferenceKeys.shortcutInsertPriority,
        FlutterPreferenceKeys.selectedContentSection,
        FlutterPreferenceKeys.firstTodoCreatedAt,
        FlutterPreferenceKeys.activationMethod,
        FlutterPreferenceKeys.installDate,
        FlutterPreferenceKeys.themeMode,
        FlutterPreferenceKeys.colorTheme,
        FlutterPreferenceKeys.selectedLocaleCode,
        FlutterPreferenceKeys.lastDashboardUpdateAt,
    ]

    static let copiedBoolKeys: [String] = [
        FlutterPreferenceKeys.linkCategoriesSeeded,
        FlutterPreferenceKeys.temporaryProTrialClaimed,
        FlutterPreferenceKeys.showTodos,
        FlutterPreferenceKeys.showMemos,
        FlutterPreferenceKeys.showCompletedTodos,
        FlutterPreferenceKeys.hasCompletedOnboarding,
        FlutterPreferenceKeys.firstTodoCreated,
        FlutterPreferenceKeys.activationCompleted,
        FlutterPreferenceKeys.lockscreenConfirmed,
        FlutterPreferenceKeys.activationEventLogged,
        FlutterPreferenceKeys.activationHasLiveActivity,
        FlutterPreferenceKeys.lockscreenPreviewSeen,
        FlutterPreferenceKeys.liveActivityStarted,
        FlutterPreferenceKeys.widgetGuideViewed,
        FlutterPreferenceKeys.nextDayOpenLogged,
        FlutterPreferenceKeys.trackingAuthorizationRequested,
        FlutterPreferenceKeys.notificationPrimerShown,
        FlutterPreferenceKeys.widgetGuideAfterFirstTodoShown,
        FlutterPreferenceKeys.widgetInstallationHandled,
        FlutterPreferenceKeys.paywallFirstLockScreenSuccess,
        FlutterPreferenceKeys.paywallDayTwoFirstOpen,
        FlutterPreferenceKeys.paywallTrialExpired,
        FlutterPreferenceKeys.reviewRequested,
        FlutterPreferenceKeys.morningReminderEnabled,
        FlutterPreferenceKeys.eveningReminderEnabled,
    ]

    static let copiedIntKeys: [String] = [
        FlutterPreferenceKeys.activationTodoCount,
        FlutterPreferenceKeys.sessionCount,
        FlutterPreferenceKeys.morningReminderHour,
        FlutterPreferenceKeys.morningReminderMinute,
        FlutterPreferenceKeys.eveningReminderHour,
        FlutterPreferenceKeys.eveningReminderMinute,
    ]

    static let copiedDoubleKeys: [String] = [
        FlutterPreferenceKeys.textScale
    ]

    enum MigrationError: Error, CustomStringConvertible {
        case notUTF8
        case notAnArray
        case cardCountMismatch(expected: Int, decoded: Int)
        case noAppGroupContainer

        var description: String {
            switch self {
            case .notUTF8: "stored cards were not valid UTF-8"
            case .notAnArray: "stored cards were not a JSON array"
            case .cardCountMismatch(let expected, let decoded):
                "decoded \(decoded) of \(expected) cards"
            case .noAppGroupContainer: "App Group container unavailable"
            }
        }
    }
}
