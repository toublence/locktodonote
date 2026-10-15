import LockTodoNoteShared
import SwiftUI

struct LayoutProfilesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var profiles: LayoutProfileStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var settings: LockScreenSettingsStore
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var showsNamePrompt = false
    @State private var name = ""
    @State private var replacement: LayoutProfile?
    @State private var message: String?
    @State private var isApplying = false

    var body: some View {
        List {
            Section {
                Text(bilingualString(
                    korean: "무료는 구성 1개를 저장합니다. Pro에서는 업무와 개인 구성을 여러 개 저장하고 바꿀 수 있습니다. 할 일과 메모는 복제하지 않습니다.",
                    english: "Free saves one layout. Pro saves multiple layouts for work and life. Your todos and notes stay in one place."
                ))
                .font(.subheadline)
                if profiles.loadFailed {
                    Text(LayoutProfileStore.ProfileError.unreadable.localizedDescription)
                        .foregroundStyle(.secondary)
                }
                Button(bilingualString(korean: "현재 구성 저장", english: "Save current layout")) {
                    replacement = nil
                    name = ""
                    if !purchases.isPro && !profiles.profiles.isEmpty {
                        environment.requestPaywall(source: "layout_profile_limit")
                    } else {
                        showsNamePrompt = true
                    }
                }
                .accessibilityIdentifier("layouts.save")
                .disabled(profiles.loadFailed || !purchases.hasResolvedEntitlement)
            }
            Section {
                NavigationLink {
                    SmartLockScreenView()
                        .modifier(ShellBackButtonModifier())
                } label: {
                    Label("Smart Lock Screen · Pro", systemImage: "clock.arrow.2.circlepath")
                        .accessibilityIdentifier("layouts.smartLockScreen")
                }
            }
            Section {
                ForEach(profiles.profiles) { profile in
                    HStack {
                        Button {
                            Task { await apply(profile) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                Text(profile.settings.template.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            Button(bilingualString(korean: "현재 구성으로 덮어쓰기", english: "Replace with current layout")) {
                                guard purchases.isPro || profiles.profiles.first?.id == profile.id else {
                                    environment.requestPaywall(source: "layout_profile_limit")
                                    return
                                }
                                replacement = profile
                                name = profile.name
                                showsNamePrompt = true
                            }
                            Button(appString(localized: "common.delete", defaultValue: "Delete"), role: .destructive) {
                                do { try profiles.remove(profile) }
                                catch { message = error.localizedDescription }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .disabled(isApplying || purchases.isPurchasing)
        .navigationTitle(bilingualString(korean: "저장한 잠금화면 구성", english: "Saved layouts"))
        .alert(bilingualString(korean: "구성 이름", english: "Layout name"), isPresented: $showsNamePrompt) {
            TextField(bilingualString(korean: "업무 또는 개인", english: "Work or personal"), text: $name)
            Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
            Button(appString(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { message = nil }
        }
    }

    private func save() {
        do {
            try profiles.save(name: name, settings: settings.settings, colorTheme: theme.colorTheme.rawValue, isPro: purchases.isPro, replacing: replacement?.id)
            analytics.layoutProfileAction("saved", count: profiles.profiles.count)
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ profile: LayoutProfile) async {
        guard purchases.hasResolvedEntitlement else { return }
        if !purchases.isPro && profiles.profiles.first?.id != profile.id {
            environment.requestPaywall(source: "layout_profile_limit")
            return
        }
        if let feature = profile.settings.template.proFeature, !purchases.canUse(feature) {
            environment.requestPaywall(source: "layout_profile_limit")
            return
        }
        isApplying = true
        defer { isApplying = false }
        do {
            settings.settings = try profiles.settingsForApplication(profile)
            theme.colorTheme = purchases.canUse(.themes)
                ? AppColorTheme(fromStored: profile.colorTheme) : .default
            dashboard.followToday()
            dashboard.publish()
            environment.liveActivity.refreshState()
            if !environment.liveActivity.state.isRunning { try await dashboard.startLiveActivity() }
            analytics.layoutProfileAction("applied", count: profiles.profiles.count)
        } catch {
            analytics.layoutProfileAction("apply_failed", count: profiles.profiles.count)
            message = error.localizedDescription
        }
    }
}
