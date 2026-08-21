import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The single door to everything the app and its extensions share: the
/// dashboard handoff payload, the work queues extensions write into, and the
/// Lock Screen image files.
public struct AppGroupStore: Sendable {
    public let suiteName: String

    public init(suiteName: String = AppGroupKeys.suiteName) {
        self.suiteName = suiteName
    }

    public var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    // MARK: - Dashboard handoff

    /// Publishes the snapshot extensions read, then refreshes the widget timeline.
    ///
    /// The flattened mirror keys (`selected_date`, `todo_items`, …) are written
    /// alongside the full payload because the shipped widget build reads them
    /// directly; dropping them would break a widget that survives the update.
    public func saveDashboardState(_ payload: [String: Any], reloadWidget: Bool = true) {
        guard let defaults else { return }
        var safe = PropertyListSanitizer.sanitize(payload)
        if safe["isPro"] == nil,
           let storedIsPro = defaults.dictionary(forKey: AppGroupKeys.dashboardState)?["isPro"] {
            safe["isPro"] = storedIsPro
        }
        defaults.set(safe, forKey: AppGroupKeys.dashboardState)
        defaults.set(safe["selectedDate"], forKey: AppGroupKeys.selectedDate)
        defaults.set(safe["todoItems"] ?? [], forKey: AppGroupKeys.todoItems)
        defaults.set(safe["memoItems"] ?? [], forKey: AppGroupKeys.memoItems)
        defaults.set(safe["showTodosOnLockScreen"] ?? true, forKey: AppGroupKeys.settingsShowTodos)
        defaults.set(safe["showMemosOnLockScreen"] ?? true, forKey: AppGroupKeys.settingsShowMemos)
        if reloadWidget { reloadWidgetTimelines() }
    }

    public func dashboardState() -> [String: Any]? {
        defaults?.dictionary(forKey: AppGroupKeys.dashboardState)
    }

    public func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupKeys.widgetKind)
        #endif
    }

    // MARK: - Completed todo queue

    public func appendPendingCompletedTodo(_ todo: PendingCompletedTodo) {
        guard let defaults else { return }
        var rows = defaults.array(forKey: AppGroupKeys.pendingCompletedTodos) as? [[String: Any]] ?? []
        guard !rows.contains(where: { $0["id"] as? String == todo.id }) else { return }
        rows.append(todo.dictionary)
        defaults.set(rows, forKey: AppGroupKeys.pendingCompletedTodos)
    }

    /// Drains both the current queue and the legacy id-only queue.
    public func drainPendingCompletedTodos() -> [PendingCompletedTodo] {
        guard let defaults else { return [] }
        let rows = defaults.array(forKey: AppGroupKeys.pendingCompletedTodos) as? [[String: Any]] ?? []
        var results = rows.compactMap(PendingCompletedTodo.init(dictionary:))

        let legacyIds = defaults.stringArray(forKey: AppGroupKeys.legacyPendingCompletedTodoIds) ?? []
        let now = Date()
        results.append(
            contentsOf: legacyIds.map {
                PendingCompletedTodo(id: $0, completedAt: now, source: "live_activity")
            }
        )

        defaults.removeObject(forKey: AppGroupKeys.pendingCompletedTodos)
        defaults.removeObject(forKey: AppGroupKeys.legacyPendingCompletedTodoIds)
        return results
    }

    // MARK: - Quick add queue

    public func appendPendingQuickAdd(_ quickAdd: PendingQuickAdd) {
        guard let defaults else { return }
        var rows = defaults.array(forKey: AppGroupKeys.pendingQuickAdds) as? [[String: Any]] ?? []
        rows.append(quickAdd.dictionary)
        defaults.set(rows, forKey: AppGroupKeys.pendingQuickAdds)
    }

    public func drainPendingQuickAdds() -> [PendingQuickAdd] {
        guard let defaults else { return [] }
        let rows = defaults.array(forKey: AppGroupKeys.pendingQuickAdds) as? [[String: Any]] ?? []
        defaults.removeObject(forKey: AppGroupKeys.pendingQuickAdds)
        return rows.compactMap(PendingQuickAdd.init(dictionary:))
    }

    // MARK: - Shared link queue

    public func drainPendingSharedLinks() -> [PendingSharedLink] {
        guard let defaults else { return [] }
        let rows = defaults.array(forKey: AppGroupKeys.pendingSharedLinks) as? [[String: Any]] ?? []
        defaults.removeObject(forKey: AppGroupKeys.pendingSharedLinks)
        return rows.compactMap(PendingSharedLink.init(dictionary:))
    }

    // MARK: - Analytics queue

    public func enqueueAnalyticsEvent(name: String, parameters: [String: Any] = [:]) {
        guard let defaults else { return }
        var rows = defaults.array(forKey: AppGroupKeys.queuedAnalyticsEvents) as? [[String: Any]] ?? []
        let event = QueuedAnalyticsEvent(name: name, parameters: parameters, createdAt: Date())
        rows.append(event.dictionary)
        defaults.set(
            Array(rows.suffix(AppGroupKeys.queuedAnalyticsEventLimit)),
            forKey: AppGroupKeys.queuedAnalyticsEvents
        )
    }

    public func queuedAnalyticsEvents() -> [QueuedAnalyticsEvent] {
        let rows = defaults?.array(forKey: AppGroupKeys.queuedAnalyticsEvents) as? [[String: Any]] ?? []
        return rows.compactMap(QueuedAnalyticsEvent.init(dictionary:))
    }

    public func clearQueuedAnalyticsEvents() {
        defaults?.removeObject(forKey: AppGroupKeys.queuedAnalyticsEvents)
    }

    // MARK: - Shortcut throttling

    public func shortcutUsageCount(on date: Date = Date()) -> Int {
        guard let defaults else { return 0 }
        let today = FlutterDate.dateKey(date)
        guard defaults.string(forKey: AppGroupKeys.shortcutUsageDate) == today else { return 0 }
        return defaults.integer(forKey: AppGroupKeys.shortcutUsageCount)
    }

    public func recordShortcutUsage(on date: Date = Date()) {
        guard let defaults else { return }
        let today = FlutterDate.dateKey(date)
        let current = defaults.string(forKey: AppGroupKeys.shortcutUsageDate) == today
            ? defaults.integer(forKey: AppGroupKeys.shortcutUsageCount)
            : 0
        defaults.set(today, forKey: AppGroupKeys.shortcutUsageDate)
        defaults.set(current + 1, forKey: AppGroupKeys.shortcutUsageCount)
    }

    // MARK: - Lock Screen images

    public var lockScreenImageDirectory: URL? {
        containerURL?.appendingPathComponent(
            AppGroupKeys.lockScreenImageDirectory,
            isDirectory: true
        )
    }

    public func lockScreenImageURL(fileName: String) -> URL? {
        lockScreenImageDirectory?.appendingPathComponent(fileName)
    }

    /// Widgets render while the device is locked, so image files must be
    /// readable after first unlock rather than only while unlocked.
    public func relaxFileProtection(at url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    /// The compact copy the Live Activity reads; its payload budget is far too
    /// small for a full-resolution image, so a downscaled JPEG lives in defaults.
    public func saveLockScreenImageData(_ data: Data, fileName: String) {
        defaults?.set(data, forKey: AppGroupKeys.lockScreenImageData(fileName: fileName))
    }

    public func lockScreenImageData(fileName: String) -> Data? {
        defaults?.data(forKey: AppGroupKeys.lockScreenImageData(fileName: fileName))
    }

    public func removeLockScreenImage(fileName: String) {
        defaults?.removeObject(forKey: AppGroupKeys.lockScreenImageData(fileName: fileName))
        if let url = lockScreenImageURL(fileName: fileName) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Card store file

    public var cardStoreURL: URL? {
        containerURL?
            .appendingPathComponent(AppGroupKeys.dataDirectory, isDirectory: true)
            .appendingPathComponent(AppGroupKeys.cardStoreFileName)
    }
}
