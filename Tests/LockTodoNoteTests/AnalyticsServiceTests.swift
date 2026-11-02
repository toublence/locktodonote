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
        service.purchaseCancelled(productId: "p", source: "paywall", attemptId: "cancel-attempt")
        service.purchaseFailed(productId: "p", source: "paywall", attemptId: "fail-attempt")
        service.restoreCompleted(result: "restored")

        #expect(backend.names() == [
            "purchase_started", "purchase_completed", "purchase_cancelled",
            "purchase_failed", "restore_completed",
        ])
        #expect(backend.parameters(for: "purchase_cancelled")?["result"] as? String == "cancelled")
        #expect(backend.parameters(for: "purchase_cancelled")?["attempt_id"] as? String == "cancel-attempt")
        #expect(backend.parameters(for: "purchase_failed")?["result"] as? String == "fail")
        #expect(backend.parameters(for: "purchase_failed")?["attempt_id"] as? String == "fail-attempt")
    }

    @Test func conversionEventsCarryNormalizedPlanAndPreviewContext() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.planSelected(
            productId: ProductIdentifiers.yearlyLegacy,
            source: "lock_screen_template",
            price: 7.7,
            currency: "USD",
            isTrial: true,
            isDefault: true,
            previewTemplate: "imageTodo"
        )

        let parameters = backend.parameters(for: "plan_selected")
        #expect(parameters?["plan"] as? String == "yearly")
        #expect(parameters?["product_id"] as? String == ProductIdentifiers.yearlyLegacy)
        #expect(parameters?["price"] as? Double == 7.7)
        #expect(parameters?["currency"] as? String == "USD")
        #expect(parameters?["is_trial"] as? Int == 1)
        #expect(parameters?["is_default"] as? Int == 1)
        #expect(parameters?["paywall_trigger"] as? String == "lock_screen_template")
        #expect(parameters?["preview_template"] as? String == "imageTodo")
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
        #expect(parameters?["analytics_schema_version"] as? Int == 2)
        #expect(parameters?["app_build"] != nil)
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

    @Test func widgetConfigurationsRecordChangesAndRemovalWithoutRepeatedDetection() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }
        service.widgetConfigurationsChecked(home: 1, rectangular: 0, inline: 0)
        #expect(backend.parameters(for: "widget_configured_detected")?["widget_configuration_state"] as? String == "home_only")
        service.widgetConfigurationsChecked(home: 1, rectangular: 0, inline: 0)
        #expect(backend.names().filter { $0 == "widget_configured_detected" }.count == 1)
        service.widgetConfigurationsChecked(home: 1, rectangular: 1, inline: 1)
        #expect(backend.parameters(for: "widget_configured_detected")?["rectangular_count"] as? Int == 1)
        service.widgetConfigurationCheckFailed(code: 7)
        #expect(backend.parameters(for: "widget_configuration_check_failed")?["widget_configuration_state"] as? String == "lock_screen")
        service.widgetConfigurationsChecked(home: 0, rectangular: 0, inline: 0)
        #expect(backend.parameters(for: "widget_configuration_checked")?["widget_configuration_state"] as? String == "none")
        #expect(backend.names().filter { $0 == "widget_configured_detected" }.count == 2)
    }

    @Test func paidRevenueSeparatesTestAndProduction() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }
        service.adRevenue(value: 0.001, currency: "USD", precision: 1)
        #expect(backend.names() == [AdPolicy.isTest ? "ad_test_revenue" : "ad_paid_revenue"])
        #expect(backend.parameters(for: backend.names()[0])?["ad_is_test"] as? Int == (AdPolicy.isTest ? 1 : 0))
    }

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

    @Test func memoCanActivateWithoutTodoAfterVerifiedSetup() {
        let suite = "test.analytics.\(UUID().uuidString)"
        defer { cleanUp(suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        let defaults = UserDefaults(suiteName: suite)!

        service.memoCreated(source: "inline", templateId: "dateMemo")
        #expect(!backend.names().contains("activation_complete"))

        defaults.set(true, forKey: FlutterPreferenceKeys.activationHasLiveActivity)
        defaults.set("live_activity_success", forKey: FlutterPreferenceKeys.activationMethod)
        service.tryCompleteActivation()

        #expect(backend.names().filter { $0 == "activation_complete" }.count == 1)
        #expect(backend.parameters(for: "activation_complete")?["content_type"] as? String == "memo")
    }

    @Test func queuedEventKeepsOriginalTimeAndAcknowledgesById() {
        let suite = "test.analytics.\(UUID().uuidString)"
        defer { cleanUp(suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)

        store.enqueueAnalyticsEvent(
            name: "todo_completed",
            parameters: ["source": "live_activity"],
            eventId: "event-1",
            createdAt: occurredAt
        )
        service.flushQueuedEvents()

        let parameters = backend.parameters(for: "todo_completed")
        #expect(parameters?["event_id"] as? String == "event-1")
        #expect(parameters?["occurred_at_ms"] as? Int64 == 1_700_000_000_000)
        #expect(store.queuedAnalyticsEvents().isEmpty)
    }

    // MARK: - Quick Add Analytics

    @Test func quickAddAnalyticsEventsRecordExpectedNamesAndParameters() {
        let (service, backend, suite) = makeService()
        defer { cleanUp(suite) }

        service.quickAddInvoked(source: "action_button", selectedTemplate: "calendarItems", isPro: false)
        service.quickAddTypeSelected(type: "todo", source: "action_button")
        service.shortcutQuickAdd(type: "todo", itemCount: 3, source: "intent", selectedTemplate: "calendarItems", isPro: false)
        service.quickAddFailed(reason: "storage_error", source: "intent")
        service.quickAddLimitReached(dailyCount: 5, source: "intent")
        service.quickAddOnboardingSeen()
        service.quickAddOnboardingCTA()
        service.quickAddTipSeen()
        service.quickAddTipTapped()
        service.quickAddEducationCompleted()

        #expect(backend.names().contains("quick_add_invoked"))
        #expect(backend.parameters(for: "quick_add_invoked")?["source"] as? String == "action_button")

        #expect(backend.names().contains("quick_add_type_selected"))
        #expect(backend.parameters(for: "quick_add_type_selected")?["type"] as? String == "todo")

        #expect(backend.names().contains("shortcut_quick_add"))
        #expect(backend.parameters(for: "shortcut_quick_add")?["type"] as? String == "todo")
        #expect(backend.parameters(for: "shortcut_quick_add")?["item_count"] as? Int == 3)

        #expect(backend.names().contains("quick_add_failed"))
        #expect(backend.parameters(for: "quick_add_failed")?["reason"] as? String == "storage_error")

        #expect(backend.names().contains("quick_add_limit_reached"))
        #expect(backend.parameters(for: "quick_add_limit_reached")?["source"] as? String == "intent")

        #expect(backend.names().contains("quick_add_onboarding_seen"))
        #expect(backend.names().contains("quick_add_onboarding_cta"))
        #expect(backend.names().contains("quick_add_tip_seen"))
        #expect(backend.names().contains("quick_add_tip_tapped"))
        #expect(backend.names().contains("quick_add_education_completed"))
    }
}


/// Capture must preserve both a todo user's display and a memo user's one-save
/// replacement flow. Rule selection always wins over a new memo default.
@Suite @MainActor
struct RebirthExperienceTests {
    @Test func regularMemoLayoutsKeepQuickReplacement() {
        for template in [LockScreenTemplate.memoTodo, .dateMemo, .imageMemo] {
            #expect(LockScreenSettings(template: template).selectsNewMemoForDisplay())
        }
        #expect(LockScreenSettings(selectedContentSection: .memo).selectsNewMemoForDisplay())
    }

    @Test func todoAndDdayCapturePreserveTheSelectedOrdinaryMemo() {
        for template in [LockScreenTemplate.calendarItems, .dateTodo, .imageTodo, .ddayMemo] {
            #expect(!LockScreenSettings(template: template).selectsNewMemoForDisplay())
        }
        #expect(!LockScreenSettings(showMemos: false, template: .memoTodo).selectsNewMemoForDisplay())
    }

    @Test func explicitScheduledMemoSelectionCannotBeReplacedByNewCapture() {
        let settings = LockScreenSettings(template: .memoTodo)
        #expect(!settings.selectsNewMemoForDisplay(allowedMemoIDs: []))
        #expect(!settings.selectsNewMemoForDisplay(allowedMemoIDs: ["existing-memo"]))
        #expect(settings.selectsNewMemoForDisplay(allowedMemoIDs: nil))
    }
}

@Suite("L1.2.2 analytics", .serialized) @MainActor
struct Release122AnalyticsTests {
    @Test func releaseIdentityAndParameterBudgetSurviveFullPurchaseAndQueuePayloads() {
        let suite = "test.L122.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        service.planSelected(productId: ProductIdentifiers.yearlyLegacy, source: "smart_repeat", price: 7.7,
            currency: "USD", isTrial: true, isDefault: true, previewTemplate: "imageTodo")
        store.enqueueAnalyticsEvent(name: "todo_completed", parameters: [
            "source": "dynamic_island", "screen_name": "lockscreen", "task_count": 30,
            "todo_count": 30, "remaining_count": 29, "completed_count": 1, "has_memo": true,
            "template_id": "memoTodo", "setup_type": "live_activity", "live_activity_enabled": true,
            "ios_version": "26.1", "device_family": "ios_activity_extension", "is_premium": true,
            "result": "success", "review_signal_recorded": true, "storage_stage": "pending_saved"
        ], createdAt: Date(timeIntervalSince1970: 1700000000))
        service.flushQueuedEvents()
        for event in backend.events {
            #expect(event.parameters.count <= 25)
            #expect(event.parameters["analytics_release"] as? String == "L1.2.2")
            #expect(event.parameters["analytics_schema_version"] as? Int == 2)
            #expect(!(event.parameters["app_version"] as? String ?? "").contains("("))
            #expect(event.parameters["app_build"] != nil)
        }
        let forwarded = backend.parameters(for: "todo_completed")
        #expect(forwarded?["occurred_at_ms"] as? Int64 == 1700000000000)
        #expect(forwarded?["forwarded_at_ms"] != nil)
        #expect(forwarded?["origin_release"] as? String == "L1.2.2")
        #expect(forwarded?["storage_stage"] as? String == "pending_saved")
        #expect(store.queuedAnalyticsEvents().isEmpty)
    }

    @Test func captureHasOneStartAndOneOutcomeAndNoContent() {
        let suite = "test.L122.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        service.captureStarted(type: "todo", source: "inline")
        service.captureStarted(type: "todo", source: "inline")
        service.captureEnded(source: "inline", result: "cancelled")
        service.captureEnded(source: "inline", result: "interrupted")
        #expect(backend.events.count == 2)
        #expect(backend.events[0].parameters["capture_id"] as? String == backend.events[1].parameters["capture_id"] as? String)
        #expect(backend.events[1].parameters["duration_bucket"] as? String == "under_10s")
        #expect(backend.events.allSatisfy { $0.parameters["text"] == nil && $0.parameters["body"] == nil })
    }

    @Test func automaticCandidateCalculationIsDeduplicatedAndPrivacyIsUnknown() {
        let suite = "test.L122.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        for _ in 0..<10 {
            service.displayCandidates(template: "dateTodo", candidates: 30, payloadLimit: 5,
                rowLimit: 4, selected: false, privacyRestricted: false)
        }
        #expect(backend.events.count == 1)
        #expect(backend.events[0].parameters["overflow"] as? Int == 1)
        service.displayCandidates(template: "dateTodo", candidates: 0, payloadLimit: 5,
            rowLimit: 4, selected: false, privacyRestricted: true)
        #expect(backend.events[1].parameters["candidate_bucket"] as? String == "unknown")
        #expect(backend.events[1].parameters["overflow"] == nil)
    }

    @Test func queueTechnicalEventsDoNotDisplaceRealActionsAndSourcesAreFinite() {
        let suite = "test.L122.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        let date = Date()
        for _ in 0..<10 { store.enqueueAnalyticsEvent(name: "widget_timeline_requested", createdAt: date) }
        #expect(store.queuedAnalyticsEvents().count == 1)
        service.quickCaptureFocused(type: "todo", source: "private user input")
        #expect(backend.events.allSatisfy { $0.parameters["source"] as? String == "unknown" })
    }

    @Test func firstCompletionRequiresSuccessfulDurableCommitAndIsOnceOnly() {
        let suite = "test.L122.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = AppGroupStore(suiteName: suite)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        store.enqueueAnalyticsEvent(name: "todo_completed", parameters: ["source": "widget", "storage_stage": "pending_saved"])
        service.flushQueuedEvents()
        #expect(!backend.names().contains("l122_first_completion"))
        store.enqueueAnalyticsEvent(name: "l122_external_commit", parameters: ["action": "complete", "result": "success", "action_origin": "widget"])
        service.flushQueuedEvents()
        service.todoCompleted(taskCount: 2, remainingCount: 0, templateId: "dateTodo")
        #expect(backend.names().filter { $0 == "l122_first_completion" }.count == 1)
    }
}

@Suite("L1.2.2 pending capture metadata")
struct Release122PendingTests {
    @Test func analyticsIdentityRoundTripsWithoutChangingLegacyQueue() {
        let id = UUID().uuidString
        let item = PendingQuickAdd(id: "fixture", text: "local only", target: .todo,
            dateKey: "2026-10-30", createdAt: Date(), analyticsEventID: id, analyticsSource: "shortcut")
        let restored = PendingQuickAdd(dictionary: item.dictionary)
        #expect(restored?.analyticsEventID == id)
        #expect(restored?.analyticsSource == "shortcut")
        var legacy = item.dictionary
        legacy.removeValue(forKey: "analytics_event_id")
        legacy.removeValue(forKey: "analytics_source")
        #expect(PendingQuickAdd(dictionary: legacy)?.analyticsEventID == nil)
        #expect(PendingQuickAdd(dictionary: legacy)?.text == item.text)
    }
}

@Suite("L1.2.2 stream migration cohort") @MainActor
struct Release122CohortTests {
    @Test func sdkFirstOpenCannotTurnAnExistingInstallIntoANewCohort() {
        let suite = "test.L122.cohort.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = AppGroupStore(suiteName: suite)
        store.defaults?.set(FlutterDate.utcString(from: Date(timeIntervalSince1970: 1700000000)), forKey: FlutterPreferenceKeys.installDate)
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: store, backend: backend)
        service.ensureInstallDate()
        service.ensureInstallDate()
        #expect(backend.names().filter { $0 == "l122_release_observed" }.count == 1)
        #expect(backend.parameters(for: "l122_release_observed")?["cohort"] as? String == "existing_or_unknown")
    }

    @Test func freshInstallHasAnExplicitNewCohort() {
        let suite = "test.L122.new.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        service.ensureInstallDate()
        #expect(backend.parameters(for: "l122_release_observed")?["cohort"] as? String == "new_observed")
    }
}

@Suite("Verified purchase metadata") @MainActor
struct Release122PurchaseMetadataTests {
    @Test func quotedTrialEligibilityIsNotARealTrial() {
        let suite = "test.L122.purchase.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        service.purchaseVerifiedEnvironment("Sandbox", trialState: .notTrial)
        service.purchaseCompleted(productId: ProductIdentifiers.monthly, source: "smart_repeat", price: 1,
            currency: "USD", isTrial: true, attemptId: "fixture-attempt")
        let parameters = backend.parameters(for: "purchase_completed")
        #expect(parameters?["is_trial"] as? Int == 0)
        #expect(parameters?["transaction_trial_state"] as? String == "not_trial")
        #expect(parameters?["transaction_environment"] as? String == "sandbox")
        #expect(parameters?["attempt_id"] as? String == "fixture-attempt")
    }

    @Test func newAttemptCannotInheritPreviousVerifiedEnvironment() {
        let suite = "test.L122.purchase.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(store: AppGroupStore(suiteName: suite), backend: backend)
        service.purchaseVerifiedEnvironment("Production", trialState: .freeTrial)
        service.purchaseStarted(productId: ProductIdentifiers.monthly, source: "smart_repeat", price: 1, currency: "USD")
        service.purchaseCompleted(productId: ProductIdentifiers.monthly, source: "smart_repeat", price: 1, currency: "USD")
        let parameters = backend.parameters(for: "purchase_completed")
        #expect(parameters?["transaction_environment"] as? String == "unknown")
        #expect(parameters?["transaction_trial_state"] as? String == "unknown")
        #expect(parameters?["is_trial"] == nil)
    }
}

#if targetEnvironment(simulator) && canImport(StoreKitTest)
import StoreKit
import StoreKitTest
import FirebaseAnalytics

/// Local Xcode StoreKit transactions only. No Store account payment is used,
/// no user cards are reset, and cleanup targets only this test transaction.
@Suite("Local StoreKit entitlement and restore", .serialized) @MainActor
struct Release122StoreKitTests {
    @Test @available(iOS 17.0, *)
    func verifiedLocalPurchaseRestoreAndRevocation() async throws {
        let suite = "test.L122.storekit.\(UUID().uuidString)"
        let store = AppGroupStore(suiteName: suite)
        let configuration = FileManager.default.temporaryDirectory.appendingPathComponent("L122-\(UUID().uuidString).storekit")
        let document: [String: Any] = [
            "identifier": UUID().uuidString,
            "nonRenewingSubscriptions": [],
            "products": [[
                "displayPrice": "9.99", "familyShareable": false, "internalID": UUID().uuidString,
                "localizations": [["description": "Local automated test only", "displayName": "QA Pro Lifetime", "locale": "en_US"]],
                "productID": ProductIdentifiers.lifetime, "referenceName": "Local QA Lifetime", "type": "NonConsumable"
            ]],
            "settings": ["_failTransactionsEnabled": false, "_locale": "en_US", "_storefront": "USA", "_storeKitErrors": []],
            "subscriptionGroups": [], "version": ["major": 3, "minor": 0]
        ]
        try JSONSerialization.data(withJSONObject: document).write(to: configuration, options: .atomic)
        // Keep simulated commerce out of the connected production Analytics project.
        Analytics.setAnalyticsCollectionEnabled(false)
        defer {
            Analytics.setAnalyticsCollectionEnabled(true)
            store.defaults?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: configuration)
        }
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        let transaction = try await session.buyProduct(identifier: ProductIdentifiers.lifetime)
        defer { try? session.deleteTransaction(identifier: UInt(transaction.id)) }
        try #require(transaction.environment == .xcode)
        await transaction.finish()
        let service = PurchaseService(store: store)
        for _ in 0..<25 {
            await service.refreshEntitlement()
            if service.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(service.isPro)
        #expect(service.entitlement.productId == ProductIdentifiers.lifetime)
        #expect(await service.restore() == .restored)
        let relaunched = PurchaseService(store: store)
        #expect(relaunched.isPro, "The same local entitlement cache survives service recreation")
        try session.refundTransaction(identifier: UInt(transaction.id))
        // StoreKit publishes revocation asynchronously, just like approval.
        // Wait for the signed entitlement sequence, not an immediate cache read.
        for _ in 0..<25 {
            await service.refreshEntitlement()
            if !service.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!service.isPro, "A revoked local transaction must not keep paid rights")
    }
}
#endif
