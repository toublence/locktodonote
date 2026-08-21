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
                .environmentObject(environment.links)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .preferredColorScheme(environment.themeStore.mode.colorScheme)
                .onOpenURL { environment.handle($0) }
                .task { await environment.bootstrap() }
                .onChange(of: scenePhase) { phase in
                    // Intents and the share extension mutate shared storage
                    // while the app is backgrounded.
                    if phase == .active { environment.refreshFromBackgroundWork() }
                }
        }
    }
}
