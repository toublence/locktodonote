import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(Darwin)
import Darwin
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
        // Duplicate foreground/activity publications must not consume WidgetKit's
        // refresh budget. Include durable input revisions so future schedules,
        // pinning and entitlement expiry still invalidate an unchanged preview.
        var needsReload = false
        if reloadWidget {
            let signature = Self.widgetReloadSignature(payload: safe, context: widgetReloadContext(defaults: defaults))
            let previous = defaults.dictionary(forKey: "glancecard.widget_reload_signature.v1")
            let now = Date().timeIntervalSince1970
            needsReload = Self.shouldReloadWidget(signature: signature, previous: previous,
                lastRequest: defaults.double(forKey: "glancecard.widget_reload_requested_at.v1"), now: now)
            if needsReload {
                defaults.set(signature, forKey: "glancecard.widget_reload_signature.v1")
                defaults.set(now, forKey: "glancecard.widget_reload_requested_at.v1")
                defaults.set(true, forKey: "glancecard.widget_reload_pending.v1")
            }
        }
        // Complete the cross-process handoff before asking extensions to read it.
        defaults.synchronize()
        if needsReload { reloadWidgetTimelines() }
    }

    static func widgetReloadSignature(payload: [String: Any], context: [String: Any]) -> [String: Any] {
        var presentation = payload
        presentation.removeValue(forKey: "updatedAt")
        return ["presentation": presentation, "inputs": context]
    }

    static func shouldReloadWidget(signature: [String: Any], previous: [String: Any]?, lastRequest: TimeInterval, now: TimeInterval) -> Bool {
        guard let previous else { return true }
        // A request is not an OS acknowledgement. Permit later publications to
        // retry an unchanged state instead of suppressing a deferred update forever.
        return now - lastRequest >= 30 || !NSDictionary(dictionary: previous).isEqual(to: signature)
    }

    private func widgetReloadContext(defaults: UserDefaults) -> [String: Any] {
        var revisions: [String: [Double]] = [:]
        for name in ["Data/cards.json", SmartLockScreenSchedule.fileName, SmartLockScreenSchedule.profilesFileName] {
            guard let url = containerURL?.appendingPathComponent(name),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date else { continue }
            revisions[name] = [modified.timeIntervalSince1970, (attributes[.size] as? NSNumber)?.doubleValue ?? 0]
        }
        let entitlement = Entitlement(cachedJSON: defaults.string(forKey: FlutterPreferenceKeys.purchaseState))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var context: [String: Any] = [
            "files": revisions,
            "followToday": defaults.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true,
            "settings": (try? encoder.encode(LockScreenSettings.load(from: defaults))) ?? Data(),
            "cachedIsPro": entitlement.isPro,
            "timeZone": TimeZone.current.identifier,
            "utcOffset": TimeZone.current.secondsFromGMT(),
            "process": ProcessInfo.processInfo.processIdentifier,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        ]
        if let expiry = entitlement.expirationDate { context["expiry"] = expiry.timeIntervalSince1970 }
        return context
    }

    /// Foreground reloads may be throttled. Send the last changed state once
    /// more at the background transition, as WidgetKit recommends.
    public func flushPendingWidgetReload() {
        guard let defaults, defaults.bool(forKey: "glancecard.widget_reload_pending.v1") else { return }
        defaults.set(false, forKey: "glancecard.widget_reload_pending.v1")
        defaults.set(Date().timeIntervalSince1970, forKey: "glancecard.widget_reload_requested_at.v1")
        defaults.synchronize()
        reloadWidgetTimelines()
    }

    public func dashboardState() -> [String: Any]? {
        defaults?.dictionary(forKey: AppGroupKeys.dashboardState)
    }

    public func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        #if DEBUG
        if let defaults, defaults.bool(forKey: "qa.widget.diagnostics.enabled") {
            let key = "qa.widget.timeline.reloadRequests"
            var requests = defaults.array(forKey: key) as? [[String: Any]] ?? []
            let items = dashboardState()?["todoItems"] as? [[String: Any]] ?? []
            requests.append(["at": Date().timeIntervalSince1970,
                             "source": Bundle.main.bundleIdentifier ?? "app",
                             "texts": items.compactMap { $0["text"] as? String }])
            defaults.set(Array(requests.suffix(12)), forKey: key)
            defaults.synchronize()
        }
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupKeys.widgetKind)
        #endif
    }

    // Queue arrays require one read/modify/write transaction across processes.
    // Keep the existing keys and payloads so installed extensions retain their work.
    private static let queueLock = NSLock()

    private func withQueueAccess<T>(_ body: () -> T) -> T {
        Self.queueLock.lock()
        defer { Self.queueLock.unlock() }
        #if canImport(Darwin)
        let directory = containerURL ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("\(suiteName).queues.lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        let locked = descriptor >= 0 && flock(descriptor, LOCK_EX) == 0
        defer {
            if locked { _ = flock(descriptor, LOCK_UN) }
            if descriptor >= 0 { close(descriptor) }
        }
        #endif
        // Flush/re-read the shared preferences while holding the process lock.
        defaults?.synchronize()
        defer { defaults?.synchronize() }
        return body()
    }

    // MARK: - Completed todo queue

    public func appendPendingCompletedTodo(_ todo: PendingCompletedTodo) {
        return withQueueAccess {
            guard let defaults else { return }
            var rows = defaults.array(forKey: AppGroupKeys.pendingCompletedTodos) as? [[String: Any]] ?? []
            guard !rows.contains(where: { $0["id"] as? String == todo.id }) else { return }
            rows.append(todo.dictionary)
            defaults.set(rows, forKey: AppGroupKeys.pendingCompletedTodos)
        }
    }

    /// Peeks without deleting. Callers acknowledge only after the card file is durable.
    public func pendingCompletedTodos() -> [PendingCompletedTodo] {
        return withQueueAccess {
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

            return results
        }
    }

    public func acknowledgePendingCompletedTodos(eventIds: Set<String>) {
        return withQueueAccess {
            guard let defaults, !eventIds.isEmpty else { return }
            let rows = defaults.array(forKey: AppGroupKeys.pendingCompletedTodos) as? [[String: Any]] ?? []
            let remaining = rows.filter {
                guard let item = PendingCompletedTodo(dictionary: $0) else { return false }
                return !eventIds.contains(item.eventId)
            }
            defaults.set(remaining, forKey: AppGroupKeys.pendingCompletedTodos)
            if eventIds.contains(where: { $0.hasPrefix("legacy-") }) {
                defaults.removeObject(forKey: AppGroupKeys.legacyPendingCompletedTodoIds)
            }
        }
    }

    // MARK: - Quick add queue

    public func appendPendingQuickAdd(_ quickAdd: PendingQuickAdd) {
        return withQueueAccess {
            guard let defaults else { return }
            var rows = defaults.array(forKey: AppGroupKeys.pendingQuickAdds) as? [[String: Any]] ?? []
            rows.append(quickAdd.dictionary)
            defaults.set(rows, forKey: AppGroupKeys.pendingQuickAdds)
            markQuickAddEducationCompleted()
            postDataChangedNotification()
        }
    }

    public func postDataChangedNotification() {
        #if canImport(Darwin)
        let name = CFNotificationName(AppGroupKeys.dataChangedNotificationName as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
        #endif
    }

    public var isQuickAddEducationCompleted: Bool {
        get { defaults?.bool(forKey: AppGroupKeys.quickAddEducationCompleted) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: AppGroupKeys.quickAddEducationCompleted) }
    }

    public func markQuickAddEducationCompleted() {
        defaults?.set(true, forKey: AppGroupKeys.quickAddEducationCompleted)
    }

    public var isQuickAddTipDismissed: Bool {
        get { defaults?.bool(forKey: AppGroupKeys.quickAddTipDismissed) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: AppGroupKeys.quickAddTipDismissed) }
    }

    public var quickAddTipImpressions: Int {
        get { defaults?.integer(forKey: AppGroupKeys.quickAddTipImpressions) ?? 0 }
        nonmutating set { defaults?.set(newValue, forKey: AppGroupKeys.quickAddTipImpressions) }
    }

    public var quickAddTipLastShownDate: String? {
        get { defaults?.string(forKey: AppGroupKeys.quickAddTipLastShownDate) }
        nonmutating set { defaults?.set(newValue, forKey: AppGroupKeys.quickAddTipLastShownDate) }
    }

    public var installDate: Date {
        if let date = defaults?.object(forKey: AppGroupKeys.installDate) as? Date {
            return date
        }
        let now = Date()
        defaults?.set(now, forKey: AppGroupKeys.installDate)
        return now
    }

    public var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    public func pendingQuickAdds() -> [PendingQuickAdd] {
        return withQueueAccess {
            guard let defaults else { return [] }
            let rows = defaults.array(forKey: AppGroupKeys.pendingQuickAdds) as? [[String: Any]] ?? []
            return rows.compactMap(PendingQuickAdd.init(dictionary:))
        }
    }

    public func acknowledgePendingQuickAdds(ids: Set<String>) {
        return withQueueAccess {
            guard let defaults, !ids.isEmpty else { return }
            let rows = defaults.array(forKey: AppGroupKeys.pendingQuickAdds) as? [[String: Any]] ?? []
            defaults.set(
                rows.filter { row in
                    guard let item = PendingQuickAdd(dictionary: row) else { return false }
                    return !ids.contains(item.id)
                },
                forKey: AppGroupKeys.pendingQuickAdds
            )
        }
    }

    // MARK: - Shared link queue

    public func drainPendingSharedLinks() -> [PendingSharedLink] {
        guard let defaults else { return [] }
        let rows = defaults.array(forKey: AppGroupKeys.pendingSharedLinks) as? [[String: Any]] ?? []
        defaults.removeObject(forKey: AppGroupKeys.pendingSharedLinks)
        return rows.compactMap(PendingSharedLink.init(dictionary:))
    }

    // MARK: - Analytics queue

    public func enqueueAnalyticsEvent(
        name: String,
        parameters: [String: Any] = [:],
        eventId: String = UUID().uuidString,
        createdAt: Date = Date()
    ) {
        return withQueueAccess {
            guard let defaults else { return }
            // Frequent OS timeline callbacks must not evict real user actions.
            if ["widget_timeline_requested", "lockscreen_activity_updated"].contains(name) {
                let key = "analytics.throttle." + name
                let last = defaults.double(forKey: key)
                guard createdAt.timeIntervalSince1970 - last >= 3600 else { return }
                defaults.set(createdAt.timeIntervalSince1970, forKey: key)
            }
            var rows = defaults.array(forKey: AppGroupKeys.queuedAnalyticsEvents) as? [[String: Any]] ?? []
            var context = parameters
            context["origin_app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            context["origin_app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            context["origin_release"] = "L1.2.2"
            #if DEBUG
            context["origin_environment"] = "debug"
            #else
            context["origin_environment"] = "release_unknown"
            #endif
            context["is_premium"] = dashboardState()?["isPro"] as? Bool == true ? 1 : 0
            let event = QueuedAnalyticsEvent(
                id: eventId,
                name: name,
                parameters: context,
                createdAt: createdAt
            )
            rows.append(event.dictionary)
            let dropped = max(0, rows.count - AppGroupKeys.queuedAnalyticsEventLimit)
            if dropped > 0 {
                defaults.set(defaults.integer(forKey: "analytics.queue_dropped_total") + dropped, forKey: "analytics.queue_dropped_total")
            }
            defaults.set(
                Array(rows.suffix(AppGroupKeys.queuedAnalyticsEventLimit)),
                forKey: AppGroupKeys.queuedAnalyticsEvents
            )
        }
    }

    public func queuedAnalyticsEvents() -> [QueuedAnalyticsEvent] {
        return withQueueAccess {
            let rows = defaults?.array(forKey: AppGroupKeys.queuedAnalyticsEvents) as? [[String: Any]] ?? []
            return rows.compactMap(QueuedAnalyticsEvent.init(dictionary:))
        }
    }

    public func acknowledgeQueuedAnalyticsEvents(ids: Set<String>) {
        return withQueueAccess {
            guard let defaults, !ids.isEmpty else { return }
            let rows = defaults.array(forKey: AppGroupKeys.queuedAnalyticsEvents) as? [[String: Any]] ?? []
            defaults.set(
                rows.filter { row in
                    guard let event = QueuedAnalyticsEvent(dictionary: row) else { return false }
                    return !ids.contains(event.id)
                },
                forKey: AppGroupKeys.queuedAnalyticsEvents
            )
        }
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
