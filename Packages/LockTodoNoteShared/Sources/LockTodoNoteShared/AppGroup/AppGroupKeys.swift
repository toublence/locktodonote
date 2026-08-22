import Foundation

/// Identifiers and storage keys shared by the app and its extensions.
///
/// Every value here is already in production use. Changing one silently
/// orphans existing user data or breaks the Live Activity handshake, so these
/// are treated as fixed constants, not configuration.
public enum AppGroupKeys {
    public static let suiteName = "group.com.namslab.glancecard"
    public static let urlScheme = "glancecard"
    public static let widgetKind = "GlanceCardLockScreenWidget"
    public static let liveActivityDashboardId = "glancecard-dashboard"

    // MARK: Dashboard handoff (written by the app, read by extensions)

    public static let dashboardState = "dashboard_state"
    public static let representativeCard = "representativeCard"
    public static let selectedDate = "selected_date"
    public static let todoItems = "todo_items"
    public static let memoItems = "memo_items"
    public static let settingsShowTodos = "settings_show_todos"
    public static let settingsShowMemos = "settings_show_memos"

    // MARK: Queues (written by extensions, drained by the app)

    public static let pendingCompletedTodos = "pending_completed_todos_v2"
    /// Superseded by `pendingCompletedTodos`; still drained so in-flight items survive.
    public static let legacyPendingCompletedTodoIds = "pending_completed_todo_ids"
    public static let pendingQuickAdds = "pending_quick_adds"
    public static let pendingSharedLinks = "pending_shared_links"
    public static let queuedAnalyticsEvents = "queued_analytics_events"
    public static let queuedAnalyticsEventLimit = 100

    // MARK: Shortcut throttling

    /// The Flutter build kept a second copy of this counter in standard
    /// UserDefaults, so the app and the intent throttled independently and a
    /// user could exceed the free daily limit. The App Group copy is now the
    /// only counter; see `ShortcutUsageLimiter`.
    public static let shortcutUsageDate = "locktodonote_shortcut_usage_date_v1"
    public static let shortcutUsageCount = "locktodonote_shortcut_usage_count_v1"
    public static let freeShortcutDailyLimit = 5

    // MARK: Images

    public static let lockScreenImageDirectory = "LockScreenImages"

    public static func lockScreenImageData(fileName: String) -> String {
        "lock_screen_image_data.\(fileName)"
    }

    // MARK: SwiftUI-era storage

    /// Card store file inside the App Group container, so intents and widgets
    /// can read the real cards instead of a flattened snapshot.
    public static let cardStoreFileName = "cards.json"
    public static let dataDirectory = "Data"

    public static let migrationVersion = "locktodonote.migration.version"
    public static let migrationCompletedAt = "locktodonote.migration.completed_at"
    public static let migrationFailureReason = "locktodonote.migration.failure_reason"
    public static let liveActivityStartedAt = "locktodonote.live_activity.started_at.v1"
    public static let liveActivityStaleLogged = "locktodonote.live_activity.stale_logged.v1"
    public static let widgetConfirmationPending = "locktodonote.widget.confirmation_pending.v1"
    public static let widgetInstallationConfirmed = "locktodonote.widget.installation_confirmed.v1"
}

/// Keys the Flutter build wrote into *standard* UserDefaults through
/// `shared_preferences`, which prefixes every key with `flutter.`.
///
/// Verified against shared_preferences 2.5.5 (`_prefix = 'flutter.'`) and the
/// app never calls `setPrefix`. Read-only: the migrator copies these forward
/// and never deletes them, which is what keeps a rollback to the Flutter build
/// possible.
public enum FlutterPreferenceKeys {
    public static let prefix = "flutter."

    public static func prefixed(_ key: String) -> String { prefix + key }

    // Cards and card-adjacent state
    public static let cards = "glancecard.cards.v1"
    public static let activeCardId = "glancecard.active_card_id.v1"
    public static let defaultPrivacyMode = "glancecard.default_privacy_mode.v1"
    public static let links = "glancecard.links.v1"
    public static let linkCategories = "glancecard.link_categories.v1"
    public static let linkCategoriesSeeded = "glancecard.link_categories_seeded.v1"

    // Purchases
    public static let purchaseState = "locktodonote_purchase_state_v1"
    public static let temporaryProTrialExpiresAt = "locktodonote.temporary_pro_trial.expires_at.v1"
    public static let temporaryProTrialClaimed = "locktodonote.temporary_pro_trial.claimed.v1"
    public static let legacyTemporaryProDay = "locktodonote.temporary_pro.day.v1"

    // Lock Screen settings
    public static let showTodos = "lockScreen.showTodos"
    public static let showMemos = "lockScreen.showMemos"
    public static let showCompletedTodos = "lockScreen.showCompletedTodos"
    public static let layout = "lockScreen.layout"
    public static let imageFileName = "lockScreen.imageFileName"
    public static let imageMemoFileName = "lockScreen.imageMemoFileName"
    public static let imageTodoFileName = "lockScreen.imageTodoFileName"
    public static let ddayTitle = "lockScreen.ddayTitle"
    public static let ddayTargetDate = "lockScreen.ddayTargetDate"
    public static let ddayMemo = "lockScreen.ddayMemo"
    public static let textFontWeight = "lockScreen.textFontWeight"
    public static let textScale = "lockScreen.textScale"
    public static let shortcutInsertPriority = "lockScreen.shortcutInsertPriority"
    public static let selectedContentSection = "lockScreen.selectedContentSection"
    public static let syncCalendarSelectionToLockScreen = "lockScreen.syncCalendarSelectionToLockScreen"

    // Onboarding and activation funnel
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let firstTodoCreated = "locktodonote.activation.first_todo_created.v1"
    public static let firstTodoCreatedAt = "locktodonote.activation.first_todo_created_at.v1"
    public static let activationMethod = "locktodonote.activation.method.v2"
    public static let activationCompleted = "locktodonote.activation.completed.v1"
    public static let lockscreenConfirmed = "locktodonote.activation.lockscreen_confirmed.v1"
    public static let activationEventLogged = "locktodonote.activation.event_logged.v2"
    public static let activationTodoCount = "locktodonote.activation.todo_count.v1"
    public static let activationHasLiveActivity = "locktodonote.activation.has_live_activity.v1"
    public static let lockscreenPreviewSeen = "locktodonote.onboarding.lockscreen_preview_seen.v1"
    public static let liveActivityStarted = "locktodonote.onboarding.live_activity_started.v1"
    public static let widgetGuideViewed = "locktodonote.onboarding.widget_guide_viewed.v1"

    // Analytics anchors and one-shot flags
    public static let installDate = "locktodonote.analytics.install_date.v1"
    public static let nextDayOpenLogged = "locktodonote.analytics.next_day_open_logged.v1"
    public static let sessionCount = "locktodonote.app_session_count.v1"
    public static let trackingAuthorizationRequested = "locktodonote.tracking_authorization_requested.v1"
    public static let notificationPrimerShown = "locktodonote.notification_primer_shown.v1"
    public static let widgetGuideAfterFirstTodoShown = "locktodonote.widget_guide_after_first_todo_shown.v1"
    public static let widgetInstallationHandled = "locktodonote.widget_installation_handled.v1"
    public static let paywallFirstLockScreenSuccess = "locktodonote.paywall.first_lock_screen_success.v1"
    public static let paywallDayTwoFirstOpen = "locktodonote.paywall.day_two_first_open.v1"
    public static let paywallTrialExpired = "locktodonote.paywall.trial_expired.v1"
    public static let reviewRequested = "locktodonote.review.requested.v1"
    public static let reviewSuccessfulUses = "locktodonote.review.successful_uses.v1"

    // Shortcut throttling (standard-defaults copy — folded into the App Group counter)
    public static let shortcutUsageDate = "locktodonote.shortcut_usage.date.v1"
    public static let shortcutUsageCount = "locktodonote.shortcut_usage.count.v1"

    // Reminders, theme, diagnostics
    public static let morningReminderEnabled = "notifications.morningReminder.enabled"
    public static let morningReminderHour = "notifications.morningReminder.hour"
    public static let morningReminderMinute = "notifications.morningReminder.minute"
    public static let eveningReminderEnabled = "notifications.eveningReminder.enabled"
    public static let eveningReminderHour = "notifications.eveningReminder.hour"
    public static let eveningReminderMinute = "notifications.eveningReminder.minute"
    public static let themeMode = "themeMode"
    public static let colorTheme = "colorTheme"
    public static let selectedLocaleCode = "selected_locale_code"
    public static let lastDashboardUpdateAt = "diagnostics.lastDashboardUpdateAt"
}
