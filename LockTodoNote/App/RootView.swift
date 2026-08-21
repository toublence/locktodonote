import StoreKit
import SwiftUI
import LockTodoNoteShared

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.requestReview) private var requestReview
    @State private var selectedDestination: PrimaryDestination = .today
    @State private var isSettingsPresented = false

    var body: some View {
        let palette = themeStore.palette(for: colorScheme)

        content(palette: palette)
            .tint(palette.accent)
            .environment(\.palette, palette)
            .background(palette.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                StorageWarningBanner()
                    .environment(\.palette, palette)
            }
            .sheet(item: $environment.quickAddRequest) { request in
                QuickAddSheet(mode: request.mode, date: request.date, source: request.source)
                    .environment(\.palette, palette)
            }
            .sheet(item: $environment.paywallRequest) { request in
                PaywallView(source: request.source)
                    .environment(\.palette, palette)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsTabView()
                    .environment(\.palette, palette)
            }
            .onChange(of: environment.pendingDeepLink) { link in
                guard let link else { return }
                route(link)
                environment.pendingDeepLink = nil
            }
            .onChange(of: environment.shouldRequestReview) { shouldRequest in
                guard shouldRequest else { return }
                requestReview()
                environment.shouldRequestReview = false
            }
            .fullScreenCover(isPresented: $environment.needsOnboarding) {
                OnboardingView { environment.completeOnboarding() }
                    .environment(\.palette, palette)
            }
    }

    private func content(palette: AppPalette) -> some View {
        AppShellView(
            selection: $selectedDestination,
            isSettingsPresented: $isSettingsPresented
        )
    }

    private func route(_ link: DeepLink) {
        switch link {
        case .quickMemo:
            selectedDestination = .today
            environment.requestQuickAdd(.memo, source: link.source ?? "app")
        case .quickTodo:
            selectedDestination = .today
            environment.requestQuickAdd(.todo, source: link.source ?? "app")
        case .dashboard:
            selectedDestination = .today
        case .card:
            // Opening a specific card lands on the day it belongs to.
            selectedDestination = .calendar
        }
    }
}

enum QuickAddMode: String, Identifiable {
    case todo
    case memo

    var id: String { rawValue }
}
