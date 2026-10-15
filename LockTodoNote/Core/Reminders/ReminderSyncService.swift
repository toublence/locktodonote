import BackgroundTasks
import Combine
import EventKit
import Foundation
import LockTodoNoteShared
import UIKit

@MainActor
final class ReminderSyncService: ObservableObject {
    nonisolated static let backgroundTaskIdentifier = "com.namslab.glancecard.reminders.refresh"
    private static weak var activeService: ReminderSyncService?

    @Published private(set) var isEnabled: Bool
    @Published private(set) var hasAccess = AppleRemindersClient.hasAccess
    @Published private(set) var lists: [AppleRemindersClient.List] = []
    @Published private(set) var selectedListIDs: Set<String>
    @Published private(set) var isSyncing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPro: Bool

    var onSync: (@MainActor () async -> Void)?
    private let cardStore: CardStore
    private let store: AppGroupStore
    private let client = AppleRemindersClient()
    private var changes: AnyCancellable?
    private var scheduledSync: Task<Void, Never>?
    private var revision = 0
    private var syncAgain = false

    var unavailableListIDs: [String] {
        selectedListIDs.subtracting(lists.map(\.id)).sorted()
    }

    init(cardStore: CardStore, store: AppGroupStore = AppGroupStore(), observeChanges: Bool = true) {
        self.cardStore = cardStore
        self.store = store
        isEnabled = store.defaults?.bool(forKey: ReminderSyncPreferences.enabledKey) ?? false
        selectedListIDs = Set(store.defaults?.stringArray(forKey: ReminderSyncPreferences.calendarsKey) ?? [])
        lastSync = store.defaults?.object(forKey: ReminderSyncPreferences.lastSyncKey) as? Date
        isPro = Entitlement(cachedJSON: store.defaults?.string(forKey: FlutterPreferenceKeys.purchaseState)).isPro
        if observeChanges {
            Self.activeService = self
            changes = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.requestSync() }
                }
        }
    }

    func refreshLists() {
        hasAccess = AppleRemindersClient.hasAccess
        lists = client.lists()
    }

    func updateEntitlement(isPro: Bool) {
        let changed = self.isPro != isPro
        self.isPro = isPro
        if changed { revision += 1 }
        if !isPro {
            scheduledSync?.cancel()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        } else if changed && isEnabled {
            requestSync()
        }
    }

    func connect() async {
        guard isPro, !isSyncing, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        errorMessage = nil
        do {
            guard try await client.requestAccess() else { throw AppleRemindersClient.SyncError.accessRequired }
            refreshLists()
            guard !lists.isEmpty else { throw AppleRemindersClient.SyncError.listUnavailable }
            if selectedListIDs.isEmpty {
                let defaultID = client.defaultListID
                selectedListIDs = [lists.first(where: { $0.id == defaultID })?.id ?? lists[0].id]
                persistSelection()
            }
            isEnabled = true
            store.defaults?.set(true, forKey: ReminderSyncPreferences.enabledKey)
            revision += 1
            _ = await synchronize()
        } catch {
            refreshLists()
            errorMessage = error.localizedDescription
        }
    }

    func setList(_ identifier: String, selected: Bool) async {
        guard isPro else { return }
        if selected { selectedListIDs.insert(identifier) }
        else { selectedListIDs.remove(identifier) }
        persistSelection()
        revision += 1
        _ = await synchronize()
    }

    func disconnect() {
        revision += 1
        scheduledSync?.cancel()
        // Remove only this app's mirrored copies, never the user's Apple reminders.
        guard cardStore.replaceReminderCopies(with: []) else {
            errorMessage = cardStore.storeError?.detail
            return
        }
        isEnabled = false
        errorMessage = nil
        store.defaults?.set(false, forKey: ReminderSyncPreferences.enabledKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    }

    func requestSync() {
        revision += 1
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard let self else { return }
            _ = await self.synchronize()
        }
    }

    @discardableResult
    func synchronize() async -> Bool {
        refreshLists()
        guard isEnabled, isPro else { return true }
        guard !isSyncing else {
            syncAgain = true
            return false
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            let currentRevision = revision
            do {
                try Task.checkCancellation()
                guard hasAccess else { throw AppleRemindersClient.SyncError.accessRequired }
                // Explicitly choosing no lists clears the mirror; missing lists on
                // an account/permission error must not be mistaken for an empty fetch.
                let records: [AppleReminderRecord]
                if selectedListIDs.isEmpty {
                    records = []
                } else {
                    let knownIDs = Set(cardStore.cards.compactMap { AppleReminderMirror.reminderID(from: $0.id) })
                    records = try await client.fetch(selectedListIDs: selectedListIDs, knownIDs: knownIDs)
                }
                try Task.checkCancellation()
                guard currentRevision == revision, isEnabled, isPro else {
                    syncAgain = isEnabled && isPro
                    continue
                }
                guard cardStore.replaceReminderCopies(with: records) else {
                    errorMessage = cardStore.storeError?.detail
                    return false
                }
                lastSync = Date()
                store.defaults?.set(lastSync, forKey: ReminderSyncPreferences.lastSyncKey)
                errorMessage = nil
                await onSync?()
            } catch is CancellationError {
                return false
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        } while syncAgain
        scheduleBackgroundRefresh()
        return true
    }

    func scheduleBackgroundRefresh() {
        guard isEnabled, isPro, AppleRemindersClient.hasAccess else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // iOS may decline scheduling (for example, Background App Refresh is off).
        // Foreground and EventKit-change synchronization remain available.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func refreshInBackground() async {
        if let service = activeService {
            _ = await service.synchronize()
            service.scheduleBackgroundRefresh()
            return
        }
        let store = AppGroupStore()
        guard let defaults = store.defaults else { return }
        let cards = CardStore(repository: CardRepository(store: store))
        guard cards.load() != nil else { return }
        let service = ReminderSyncService(cardStore: cards, store: store, observeChanges: false)
        let isPro = service.isPro
        service.onSync = {
            let settings = LockScreenSettings.load(from: defaults)
            let followsToday = store.defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
            let selectedDate = followsToday ? Date() : store.defaults?.string(forKey: AppGroupKeys.selectedDate)
                .flatMap { FlutterDate.date(fromKey: $0) } ?? Date()
            let resolved = SmartLockScreenSchedule.resolve(
                cards: cards.cards, settings: settings, store: store, at: Date(), isPro: isPro
            )
            let snapshot = DashboardComposer(
                strings: .current,
                localeIdentifier: AppLanguagePreference.resolvedLocaleIdentifier(from: store.defaults)
            ).compose(
                cards: resolved.cards, selectedDate: resolved.ruleID == nil ? selectedDate : Date(), settings: resolved.settings,
                privacyMode: PrivacyMode(fromStored: store.defaults?.string(forKey: FlutterPreferenceKeys.defaultPrivacyMode))
            )
            store.saveDashboardState(snapshot.dictionary(isPro: isPro))
            await LiveActivityService(store: store).update(snapshot: snapshot, isPro: isPro)
        }
        _ = await service.synchronize()
        service.scheduleBackgroundRefresh()
    }

    private func persistSelection() {
        store.defaults?.set(selectedListIDs.sorted(), forKey: ReminderSyncPreferences.calendarsKey)
    }
}
