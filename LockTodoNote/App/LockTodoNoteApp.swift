import SwiftUI

@main
struct LockTodoNoteApp: App {
    @StateObject private var environment = AppEnvironment()
    @StateObject private var languageStore = AppLanguageStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before any other Firebase component starts up.
        FirebaseBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.cardStore)
                .environmentObject(environment.themeStore)
                .environmentObject(environment.settingsStore)
                .environmentObject(environment.purchases)
                .environmentObject(environment.liveActivity)
                .environmentObject(environment.dashboard)
                .environmentObject(environment.analytics)
                .environmentObject(environment.ads)
                .environmentObject(environment.notifications)
                .environmentObject(environment.links)
                .environmentObject(environment.layoutProfiles)
                .environmentObject(environment.lockScreenSchedule)
                .environmentObject(environment.reminderSync)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    environment.smartLockScreen.refresh()
                }
                .onOpenURL { environment.handle($0) }
                .task {
                    await environment.bootstrap()
                    environment.smartLockScreen.setActive(true)
                }
                .onChange(of: scenePhase) { phase in
                    // Intents and the share extension mutate shared storage
                    // while the app is backgrounded.
                    if phase == .active {
                        environment.refreshFromBackgroundWork()
                        environment.smartLockScreen.setActive(true)
                    }
                    if phase == .background {
                        environment.smartLockScreen.setActive(false)
                        environment.reminderSync.scheduleBackgroundRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(SmartLockScreenService.backgroundTaskIdentifier)) {
            await SmartLockScreenService.refreshInBackground()
        }
        .backgroundTask(.appRefresh(ReminderSyncService.backgroundTaskIdentifier)) {
            await ReminderSyncService.refreshInBackground()
        }
    }
}
