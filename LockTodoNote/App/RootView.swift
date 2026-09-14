import AppTrackingTransparency
import StoreKit
import SwiftUI
import UIKit
import LockTodoNoteShared

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.requestReview) private var requestReview
    @State private var selectedDestination: PrimaryDestination = .today
    @State private var hasLeftForeground = false
    @State private var leftForegroundAt: Date?
    @State private var isRequestingTrackingAuthorization = false

    var body: some View {
        let palette = themeStore.palette(for: colorScheme)

        content(palette: palette)
            // RootView observes ThemeStore directly, so changing the picker
            // updates the whole app immediately instead of only after relaunch.
            .preferredColorScheme(themeStore.mode.colorScheme)
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
            .sheet(item: $environment.memoEditorRequest) { card in
                MemoEditorSheet(card: card)
                    .environment(\.palette, palette)
            }
            .alert(
                bilingualString(
                    korean: "오늘 무료 단축어 사용 횟수를 모두 사용했어요.",
                    english: "You've used all free Shortcut adds today."
                ),
                isPresented: $environment.showShortcutLimitPrompt
            ) {
                Button(bilingualString(korean: "Pro 보기", english: "View Pro")) {
                    environment.offerPaywallForShortcutLimit()
                }
                Button(appString(localized: "common.notNow", defaultValue: "Not now"), role: .cancel) {}
            } message: {
                Text(bilingualString(
                    korean: "Pro에서는 제한 없이 추가할 수 있습니다.",
                    english: "With Pro, you can add without limits."
                ))
            }
            .confirmationDialog(
                bilingualString(korean: "언제 오늘 할 일을 알려드릴까요?", english: "When should we remind you about today's tasks?"),
                isPresented: $environment.showReminderSuggestion,
                titleVisibility: .visible
            ) {
                Button(bilingualString(korean: "아침 8시", english: "8:00 AM")) {
                    Task { await environment.enableSuggestedReminder(morning: true) }
                }
                Button(bilingualString(korean: "저녁 9시", english: "9:00 PM")) {
                    Task { await environment.enableSuggestedReminder(morning: false) }
                }
                Button(appString(localized: "common.notNow", defaultValue: "Not now"), role: .cancel) {
                    environment.dismissReminderSuggestion()
                }
            }
            .alert(
                environment.deepLinkError ?? "",
                isPresented: Binding(
                    get: { environment.deepLinkError != nil },
                    set: { if !$0 { environment.deepLinkError = nil } }
                )
            ) {
                Button(appString(localized: "common.ok", defaultValue: "OK")) {
                    environment.deepLinkError = nil
                }
            }
            .onChange(of: environment.pendingDeepLink) { link in
                guard let link else { return }
                route(link)
                environment.pendingDeepLink = nil
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else {
                    hasLeftForeground = true
                    leftForegroundAt = Date()
                    return
                }
                if !environment.needsOnboarding {
                    Task { await requestTrackingAuthorizationIfNeeded() }
                }
                guard hasLeftForeground else { return }
                guard let leftForegroundAt,
                      Date().timeIntervalSince(leftForegroundAt) >= 5
                else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.75))
                    guard scenePhase == .active else { return }
                    let blocked = environment.needsOnboarding
                        || environment.quickAddRequest != nil
                        || environment.paywallRequest != nil
                        || environment.isProInfoPresented
                        || environment.purchases.isPurchasing
                        || selectedDestination == .settings
                        || UIApplication.shared.hasActiveTextInput
                    if environment.reviewCoordinator.claimForegroundRequest(isBlocked: blocked) {
                        requestReview()
                    }
                }
            }
            .fullScreenCover(isPresented: $environment.needsOnboarding) {
                OnboardingView {
                    Task { await finishOnboardingAfterTrackingAuthorization() }
                }
                    .environment(\.palette, palette)
            }
            .task {
                guard !environment.needsOnboarding else { return }
                await requestTrackingAuthorizationIfNeeded()
            }
    }

    private func content(palette: AppPalette) -> some View {
        AppShellView(selection: $selectedDestination)
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
        case .card(let id):
            selectedDestination = .calendar
            environment.openCard(id: id)
        }
    }

    @MainActor
    private func finishOnboardingAfterTrackingAuthorization() async {
        environment.completeOnboarding()
        _ = await requestTrackingAuthorizationIfNeeded()
    }

    @MainActor
    @discardableResult
    private func requestTrackingAuthorizationIfNeeded() async -> Bool {
        guard scenePhase == .active,
              !isRequestingTrackingAuthorization
        else { return false }

        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        guard currentStatus == .notDetermined else { return true }

        isRequestingTrackingAuthorization = true
        defer { isRequestingTrackingAuthorization = false }

        _ = await ATTrackingManager.requestTrackingAuthorization()
        return true
    }
}

enum QuickAddMode: String, Identifiable {
    case todo
    case memo

    var id: String { rawValue }
}

private extension UIApplication {
    var hasActiveTextInput: Bool {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { window in
                window.findFirstResponder() != nil
            }
    }
}

private extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for child in subviews {
            if let responder = child.findFirstResponder() { return responder }
        }
        return nil
    }
}
