import ActivityKit
import Foundation
import LockTodoNoteShared

/// Starts, refreshes, and ends the Lock Screen card.
///
/// This replaces the Flutter MethodChannel bridge: the snapshot no longer makes
/// a round trip through a `[String: Any]` dictionary, so the app and the
/// extension now share one typed model.
@MainActor
final class LiveActivityService: ObservableObject {
    /// Matches the Flutter build, which let an activity go stale after 12 hours.
    static let activityDuration: TimeInterval = 12 * 60 * 60

    @Published private(set) var state: ActivityState = .notStarted

    private let store: AppGroupStore

    init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
        refreshState()
    }

    enum ActivityState: Equatable {
        case notStarted
        case active(startedAt: Date)
        /// Running but past its stale date — iOS dims it and stops trusting it.
        case possiblyExpired
        case unsupported(reason: String)

        var isRunning: Bool {
            switch self {
            case .active, .possiblyExpired: true
            case .notStarted, .unsupported: false
            }
        }
    }

    enum LiveActivityError: LocalizedError {
        case unsupportedOSVersion
        case disabledInSettings
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedOSVersion:
                appString(localized: "liveActivity.unsupported",
                    defaultValue: "Live Activities need iOS 16.2 or later."
                )
            case .disabledInSettings:
                appString(localized: "liveActivity.disabled",
                    defaultValue: "Live Activities are turned off for LockTodoNote in Settings."
                )
            case .startFailed(let detail):
                detail
            }
        }

        /// Reason string for the analytics failure event.
        var analyticsReason: String {
            switch self {
            case .unsupportedOSVersion: "unsupported_os"
            case .disabledInSettings: "activities_disabled"
            case .startFailed: "request_failed"
            }
        }
    }

    // MARK: - Lifecycle

    /// Publishes the snapshot and starts a fresh activity, replacing any
    /// existing one so a stale card can never linger alongside a new one.
    func start(snapshot: DashboardSnapshot, isPro: Bool) async throws {
        guard #available(iOS 16.2, *) else { throw LiveActivityError.unsupportedOSVersion }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.disabledInSettings
        }

        await endAll()
        store.defaults?.removeObject(forKey: AppGroupKeys.liveActivityStartedAt)
        store.saveDashboardState(snapshot.dictionary(isPro: isPro))

        do {
            _ = try Activity.request(
                attributes: GlanceDashboardAttributes(),
                content: ActivityContent(
                    state: .init(snapshot: snapshot),
                    staleDate: Date().addingTimeInterval(Self.activityDuration)
                ),
                pushType: nil
            )
            store.defaults?.set(
                Date().timeIntervalSince1970,
                forKey: AppGroupKeys.liveActivityStartedAt
            )
            refreshState()
        } catch {
            refreshState()
            throw LiveActivityError.startFailed(error.localizedDescription)
        }
    }

    /// Pushes new content to the running activity, or starts one if the user
    /// has content but no activity — the Flutter bridge did the same.
    func update(snapshot: DashboardSnapshot, isPro: Bool) async {
        guard #available(iOS 16.2, *) else { return }
        store.saveDashboardState(snapshot.dictionary(isPro: isPro))
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<GlanceDashboardAttributes>.activities
        guard !activities.isEmpty else { return }

        let content = ActivityContent(
            state: GlanceDashboardAttributes.ContentState(snapshot: snapshot),
            staleDate: Date().addingTimeInterval(Self.activityDuration)
        )
        for activity in activities {
            await activity.update(content)
        }
        refreshState()
    }

    func end() async {
        await endAll()
        store.defaults?.removeObject(forKey: AppGroupKeys.liveActivityStartedAt)
        refreshState()
    }

    private func endAll() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<GlanceDashboardAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - State

    func refreshState() {
        guard #available(iOS 16.2, *) else {
            state = .unsupported(reason: "os")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .unsupported(reason: "disabled")
            return
        }
        guard let activity = Activity<GlanceDashboardAttributes>.activities.first else {
            state = .notStarted
            return
        }
        let storedStartedAt = store.defaults?.double(forKey: AppGroupKeys.liveActivityStartedAt) ?? 0
        let startedAt = storedStartedAt > 0
            ? Date(timeIntervalSince1970: storedStartedAt)
            : Date(timeIntervalSince1970: activity.content.state.updatedAt)
        state = Date().timeIntervalSince(startedAt) > Self.activityDuration
            ? .possiblyExpired
            : .active(startedAt: startedAt)
    }
}
