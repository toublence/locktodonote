import Foundation
import Testing

@testable import LockTodoNote
@testable import LockTodoNoteShared

/// The Firebase dashboards that already exist are keyed by event name. Renaming
/// one splits its history in two, so these tests pin the names and the
/// parameters the Flutter build sent.
@MainActor
@Suite("Analytics event contract", .serialized)
struct AnalyticsServiceTests {
    private func makeService() -> (AnalyticsService, RecordingAnalyticsBackend, String) {
        let suite = "test.analytics.\(UUID().uuidString)"
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        return (service, backend, suite)
    }

    private func cleanUp(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    // MARK: - Names carried over from the Flutter build

    @Test func onboardingEventsKeepTheirNames() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.onboardingStart()
        service.onboardingStepViewed(step: "intro", index: 1)
        service.onboardingComplete(skipped: false)

        #expect(backend.names() == ["onboarding_start", "onboarding_step_view", "onboarding_complete"])
    }

    @Test func paywallEventUsesSeenNotViewed() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.paywallSeen(source: "settings_pro_card")

        // The Flutter build logged `paywall_seen`; `paywall_viewed` would be a
        // different, empty series in the dashboard.
        #expect(backend.names() == ["paywall_seen"])
        #expect(backend.parameters(for: "paywall_seen")?["paywall_trigger"] as? String == "settings_pro_card")
    }

    @Test func liveActivityStartUsesTheSuccessName() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.liveActivityStarted(
            taskCount: 3, remainingCount: 2, hasMemo: true, templateId: "calendarItems"
        )

        #expect(backend.names().contains("live_activity_start_success"))
        let parameters = backend.parameters(for: "live_activity_start_success")
        #expect(parameters?["template_id"] as? String == "calendarItems")
        #expect(parameters?["todo_count"] as? Int == 3)
        #expect(parameters?["remaining_count"] as? Int == 2)
    }

    @Test func purchaseFunnelNamesAreStable() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.purchaseStarted(productId: "p", source: "paywall", price: 4.99, currency: "USD")
        service.purchaseCompleted(productId: "p", source: "paywall", price: 4.99, currency: "USD")
        service.purchaseCancelled(productId: "p", source: "paywall")
        service.purchaseFailed(productId: "p", source: "paywall")
        service.restoreCompleted(restored: true)

        #expect(backend.names() == [
            "purchase_started", "purchase_completed", "purchase_cancelled",
            "purchase_failed", "restore_completed",
        ])
    }

    // MARK: - Parameter shape

    @Test func booleansAreCoercedToNumbers() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.todoCreated(taskCount: 1, remainingCount: 1, hasMemo: true, templateId: "dateTodo")

        // Firebase rejects Bool parameters; the Flutter build sent 0/1.
        let parameters = backend.parameters(for: "todo_created")
        #expect(parameters?["has_memo"] as? Int == 1)
        #expect(parameters?["is_first_todo"] as? Int == 1)
    }

    @Test func everyEventCarriesTheCommonParameters() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.ddaySet()

        let parameters = backend.parameters(for: "dday_set")
        #expect(parameters?["app_version"] != nil)
        #expect(parameters?["days_since_install"] != nil)
        #expect(parameters?["is_premium"] as? Int == 0)
        #expect(parameters?["device_family"] as? String == "ios")
        #expect(parameters?["language"] != nil)
    }

    @Test func premiumFlagFollowsEntitlement() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.isPremium = true
        service.ddaySet()

        #expect(backend.parameters(for: "dday_set")?["is_premium"] as? Int == 1)
    }

    // MARK: - First-todo funnel

    @Test func firstTodoLogsBothEventsThenOnlyTheGeneralOne() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.todoCreated(taskCount: 1, remainingCount: 1, hasMemo: false, templateId: "dateTodo")
        #expect(backend.names() == ["todo_created", "first_todo_created"])

        service.todoCreated(taskCount: 2, remainingCount: 2, hasMemo: false, templateId: "dateTodo")
        #expect(
            backend.names().filter { $0 == "first_todo_created" }.count == 1,
            "first_todo_created fires once per install"
        )
    }

    // MARK: - Migration

    @Test func migrationOutcomesReportOnlyWhenSomethingHappened() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.record(migration: .alreadyMigrated)
        service.record(migration: .nothingToMigrate)
        #expect(backend.names().isEmpty, "a no-op migration is not an event")

        service.record(migration: .migrated(cardCount: 12))
        #expect(backend.parameters(for: "migration_completed")?["card_count"] as? Int == 12)

        service.record(migration: .failed(reason: "boom"))
        #expect(backend.parameters(for: "migration_failed")?["result"] as? String == "fail")
    }

    // MARK: - Extension queue

    @Test func queuedExtensionEventsAreForwardedWithTheirDelay() throws {
        let suite = "test.analytics.\(UUID().uuidString)"
        defer { cleanUp(suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)

        store.enqueueAnalyticsEvent(name: "todo_completed", parameters: ["source": "live_activity"])
        service.flushQueuedEvents()

        #expect(backend.names() == ["todo_completed"])
        let parameters = backend.parameters(for: "todo_completed")
        #expect(parameters?["source"] as? String == "live_activity")
        // Firebase stamps receipt time, so the delay is attached to keep the
        // distortion measurable.
        #expect(parameters?["queued_delay_hours"] != nil)
        #expect(store.queuedAnalyticsEvents().isEmpty, "the queue is drained after a successful flush")
    }

    @Test func activationCompletesOnlyWhenBothSignalsArePresent() {
        let suite = "test.analytics.\(UUID().uuidString)"
        defer { cleanUp(suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        let defaults = UserDefaults(suiteName: suite)!

        // A todo alone is not activation.
        service.todoCreated(taskCount: 1, remainingCount: 1, hasMemo: false, templateId: "dateTodo")
        #expect(!backend.names().contains("activation_complete"))

        // Getting the card onto the Lock Screen completes it.
        defaults.set(true, forKey: FlutterPreferenceKeys.activationHasLiveActivity)
        defaults.set("live_activity_success", forKey: FlutterPreferenceKeys.activationMethod)
        service.tryCompleteActivation()

        #expect(backend.names().contains("activation_complete"))
        #expect(service.hasCompletedActivation)

        // And never fires twice.
        service.tryCompleteActivation()
        #expect(backend.names().filter { $0 == "activation_complete" }.count == 1)
    }
}
