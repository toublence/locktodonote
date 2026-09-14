import SwiftUI
import LockTodoNoteShared

/// Settings keeps the Flutter build's ordering so returning users find things
/// where they left them.
struct SettingsTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var notifications: NotificationService
    @Environment(\.openURL) private var openURL
    @Environment(\.palette) private var palette

    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                proSection
                settingsDestinations
                aboutSection
                migrationSection
            }
            .accessibilityIdentifier("settings.root")
            .environment(\.defaultMinListRowHeight, 40)
            .modifier(CompactSettingsFormModifier())
            .toolbar(.hidden, for: .navigationBar)
            .task { await notifications.refreshAuthorizationStatus() }
            .alert(
                restoreMessage ?? "",
                isPresented: Binding(
                    get: { restoreMessage != nil },
                    set: { if !$0 { restoreMessage = nil } }
                )
            ) {
                Button(appString(localized: "common.ok", defaultValue: "OK")) { restoreMessage = nil }
            }
        }
    }

    // MARK: - Sections

    private var settingsDestinations: some View {
        Section {
            NavigationLink {
                VStack(spacing: 0) {
                    DashboardPreviewCard(snapshot: dashboard.currentSnapshot())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(palette.background)

                    Form {
                        textStyleSection
                        privacySection
                        appearanceSection
                    }
                }
                .background(palette.background)
                .navigationTitle(
                    appString(localized: "settings.appearance", defaultValue: "Appearance")
                )
            } label: {
                Label(
                    appString(localized: "settings.appearance", defaultValue: "Appearance"),
                    systemImage: "rectangle.on.rectangle.angled"
                )
            }

            NavigationLink {
                Form { remindersSection }
                    .navigationTitle(
                        appString(localized: "settings.morningBriefing", defaultValue: "Morning Briefing")
                    )
            } label: {
                Label(
                    appString(localized: "settings.morningBriefing", defaultValue: "Morning Briefing"),
                    systemImage: "sunrise"
                )
            }

            NavigationLink {
                DisplayContinuityView()
                    .navigationTitle(
                        appString(localized: "settings.liveAndWidget", defaultValue: "Live Activity & Widget")
                    )
            } label: {
                Label(
                    appString(localized: "settings.liveAndWidget", defaultValue: "Live Activity & Widget"),
                    systemImage: "lock.rectangle"
                )
            }

            NavigationLink {
                Form {
                    Section {
                        Text(
                            appString(localized: "settings.dataDetail",
                                defaultValue: "Your cards remain in the existing LockTodoNote App Group so updates keep your data."
                            )
                        )
                        .foregroundStyle(palette.textSecondary)
                    }
                    migrationSection
                }
                .navigationTitle(
                    appString(localized: "settings.syncData", defaultValue: "Sync & Data")
                )
            } label: {
                Label(
                    appString(localized: "settings.syncData", defaultValue: "Sync & Data"),
                    systemImage: "externaldrive"
                )
            }

            NavigationLink {
                LanguageSettingsView()
            } label: {
                LabeledContent {
                    Text(languageStore.selection.displayName)
                        .foregroundStyle(palette.textSecondary)
                } label: {
                    Label(appString(localized: "settings.language", defaultValue: "Language"), systemImage: "globe")
                }
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if purchases.isPro {
                LabeledContent {
                    Text(planName)
                        .foregroundStyle(palette.textSecondary)
                } label: {
                    Label(
                        appString(localized: "settings.proActive", defaultValue: "LockTodoNote Pro"),
                        systemImage: "checkmark.seal.fill"
                    )
                }
                if let expiry = purchases.entitlement.expirationDate {
                    LabeledContent(
                        appString(localized: "settings.renewsOn", defaultValue: "Renews"),
                        value: appDateString(expiry)
                    )
                }
                if environment.pendingProPreview != nil {
                    Button(appString(localized: "purchase.retryApply", defaultValue: "Apply purchased preview again")) {
                        Task {
                            let result = await environment.applyPendingProValue()
                            restoreMessage = result.succeeded
                                ? appString(localized: "purchase.applied", defaultValue: "Your Pro preview was applied.")
                                : appString(localized: "purchase.applyFailed", defaultValue: "The preview could not be applied. Please try again.")
                        }
                    }
                }
            } else {
                Button {
                    environment.requestPaywall(source: "settings_pro_card")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appString(localized: "settings.getPro", defaultValue: "Get LockTodoNote Pro"))
                                .foregroundStyle(palette.textPrimary)
                            Text(
                                appString(localized: "settings.getProDetail",
                                    defaultValue: "Photo and D-Day templates, unlimited Shortcuts."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if purchases.entitlement.temporaryTrialActive {
                    Label(
                        appString(localized: "settings.trialActive",
                            defaultValue: "Pro templates unlocked for 24 hours"
                        ),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.accent)
                }
            }

            Button(appString(localized: "paywall.restore", defaultValue: "Restore purchases")) {
                Task {
                    let outcome = await purchases.restore()
                    let result: String
                    switch outcome {
                    case .restored: result = "restored"
                    case .noPurchases: result = "no_purchases"
                    case .failed: result = "failed"
                    }
                    analytics.restoreCompleted(result: result)
                    switch outcome {
                    case .restored:
                        restoreMessage = appString(localized: "restore.success",
                            defaultValue: "Your purchase was restored."
                        )
                    case .noPurchases:
                        restoreMessage = appString(localized: "restore.empty",
                            defaultValue: "No previous purchase was found for this Apple Account."
                        )
                    case .failed:
                        restoreMessage = appString(localized: "restore.failed",
                            defaultValue: "Purchases could not be restored. Please try again."
                        )
                    }
                }
            }
        }
    }

    private var planName: String {
        switch purchases.entitlement.kind {
        case .monthly: appString(localized: "product.monthly", defaultValue: "Monthly")
        case .yearly: appString(localized: "product.yearly", defaultValue: "Yearly")
        case .lifetime: appString(localized: "product.lifetime", defaultValue: "Lifetime")
        case nil: ""
        }
    }

    private var textStyleSection: some View {
        Section {
            Picker(
                appString(localized: "settings.fontWeight", defaultValue: "Text weight"),
                selection: binding(\.textFontWeight)
            ) {
                Text(appString(localized: "settings.weightRegular", defaultValue: "Regular")).tag("regular")
                Text(appString(localized: "settings.weightBold", defaultValue: "Bold")).tag("bold")
            }
            VStack(alignment: .leading) {
                Text(appString(localized: "settings.textSize", defaultValue: "Text size"))
                Slider(
                    value: binding(\.textScale),
                    in: LockScreenSettings.minTextScale...LockScreenSettings.maxTextScale,
                    step: 0.05
                )
                .accessibilityValue(String(format: "%.0f%%", settingsStore.settings.textScale * 100))
            }
        } header: {
            Text(appString(localized: "settings.textStyle", defaultValue: "Lock Screen text"))
        }
    }

    private var privacySection: some View {
        Section {
            Picker(
                appString(localized: "settings.privacyMode", defaultValue: "Show on Lock Screen"),
                selection: $settingsStore.defaultPrivacyMode
            ) {
                ForEach(PrivacyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } footer: {
            Text(settingsStore.defaultPrivacyMode.explanation)
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(
                appString(localized: "settings.morningReminder", defaultValue: "Morning reminder"),
                isOn: Binding(
                    get: { notifications.settings.morningEnabled },
                    set: { enabled in
                        Task { await setReminder(morning: true, enabled: enabled) }
                    }
                )
            )
            if notifications.settings.morningEnabled {
                DatePicker(
                    appString(localized: "settings.time", defaultValue: "Time"),
                    selection: Binding(
                        get: { notifications.settings.time(morning: true) },
                        set: { notifications.settings.setTime($0, morning: true) }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle(
                appString(localized: "settings.eveningReminder", defaultValue: "Evening reminder"),
                isOn: Binding(
                    get: { notifications.settings.eveningEnabled },
                    set: { enabled in
                        Task { await setReminder(morning: false, enabled: enabled) }
                    }
                )
            )
            if notifications.settings.eveningEnabled {
                DatePicker(
                    appString(localized: "settings.time", defaultValue: "Time"),
                    selection: Binding(
                        get: { notifications.settings.time(morning: false) },
                        set: { notifications.settings.setTime($0, morning: false) }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text(appString(localized: "settings.reminders", defaultValue: "Reminders"))
        } footer: {
            if notifications.authorizationStatus == .denied {
                Text(
                    appString(localized: "settings.notificationsDenied",
                        defaultValue: "Notifications are turned off for LockTodoNote in Settings."
                    )
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(
                appString(localized: "settings.theme", defaultValue: "Theme"),
                selection: $themeStore.mode
            ) {
                Text(appString(localized: "settings.themeSystem", defaultValue: "System")).tag(AppThemeMode.system)
                Text(appString(localized: "settings.themeLight", defaultValue: "Light")).tag(AppThemeMode.light)
                Text(appString(localized: "settings.themeDark", defaultValue: "Dark")).tag(AppThemeMode.dark)
            }

            NavigationLink {
                ColorThemePicker()
            } label: {
                HStack {
                    Text(appString(localized: "settings.accent", defaultValue: "Accent colour"))
                    Spacer()
                    Circle()
                        .fill(themeStore.colorTheme.palette.display)
                        .frame(width: 20, height: 20)
                    if !purchases.canUse(.themes) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section(appString(localized: "settings.about", defaultValue: "About")) {
            Link(
                appString(localized: "settings.privacy", defaultValue: "Privacy Policy"),
                destination: LegalLinks.privacyPolicy
            )
            Link(
                appString(localized: "settings.terms", defaultValue: "Terms of Use"),
                destination: LegalLinks.termsOfUse
            )
            Button {
                openReviewPage()
            } label: {
                Label(
                    appString(localized: "settings.rateReview", defaultValue: "Rate & Review"),
                    systemImage: "star.bubble"
                )
                .foregroundStyle(palette.textPrimary)
            }
            LabeledContent(
                appString(localized: "settings.version", defaultValue: "Version"),
                value: AppInfo.versionDisplay
            )
        }
    }

    @ViewBuilder
    private var migrationSection: some View {
        if let outcome = environment.migrationOutcome, case .failed(let reason) = outcome {
            Section {
                Label(
                    appString(localized: "settings.migrationFailed",
                        defaultValue: "Your previous data could not be read yet. It is still saved and will be retried on the next launch."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(palette.warning)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    /// Writes through to the settings store and republishes the Lock Screen.
    private func binding<Value>(
        _ keyPath: WritableKeyPath<LockScreenSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.settings[keyPath: keyPath] = newValue
                dashboard.publish()
            }
        )
    }

    private func setReminder(morning: Bool, enabled: Bool) async {
        let kind = morning ? "morning" : "evening"
        if enabled, notifications.authorizationStatus != .authorized {
            let granted = await notifications.requestAuthorization()
            analytics.reminderAction(granted ? "permission_granted" : "permission_denied", kind: kind)
            guard granted else { return }
        }
        if morning {
            notifications.settings.morningEnabled = enabled
        } else {
            notifications.settings.eveningEnabled = enabled
        }
        analytics.reminderAction(enabled ? "enabled" : "disabled", kind: kind)
    }

    private func openReviewPage() {
        openURL(AppInfo.reviewURL) { accepted in
            if accepted {
                analytics.reviewStoreLinkOpened()
            } else {
                restoreMessage = appString(
                    localized: "review.storeUnavailable",
                    defaultValue: "The App Store review page could not be opened."
                )
            }
        }
    }
}

private struct CompactSettingsFormModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .contentMargins(.top, 0, for: .scrollContent)
                .listSectionSpacing(.compact)
        } else {
            content
        }
    }
}

private struct LanguageSettingsView: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        languageStore.select(language)
                        dashboard.publish()
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if languageStore.selection == language {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        languageStore.selection == language ? [.isButton, .isSelected] : .isButton
                    )
                }
            } footer: {
                Text(
                    languageStore.selection == .system
                        ? appString(localized: "settings.languageDetail",
                            defaultValue: "System Default follows the language selected for the app in iOS Settings."
                        )
                        : appString(localized: "settings.languageApplied",
                            defaultValue: "The selected language is used in the app, Live Activity, and Widget."
                        )
                )
            }
        }
        .navigationTitle(appString(localized: "settings.language", defaultValue: "Language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ColorThemePicker: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.palette) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AppColorTheme.selectable) { theme in
                    Button {
                        select(theme)
                    } label: {
                        Circle()
                            .fill(theme.palette.display)
                            .frame(height: 52)
                            .overlay(
                                Circle().stroke(
                                    themeStore.colorTheme == theme ? palette.textPrimary : .clear,
                                    lineWidth: 2
                                )
                            )
                            .overlay {
                                if themeStore.colorTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.rawValue)
                    .accessibilityAddTraits(
                        themeStore.colorTheme == theme ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
            .padding(20)

            if !purchases.canUse(.themes) {
                Text(
                    appString(localized: "settings.themesPro",
                        defaultValue: "Accent colours are part of Pro."
                    )
                )
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20)
            }
        }
        .background(palette.background)
        .navigationTitle(appString(localized: "settings.accent", defaultValue: "Accent colour"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ theme: AppColorTheme) {
        guard purchases.canUse(.themes) else {
            environment.requestPaywall(source: "theme_color")
            return
        }
        themeStore.colorTheme = theme
    }
}

extension PrivacyMode {
    var displayName: String {
        switch self {
        case .full: appString(localized: "privacy.full", defaultValue: "Everything")
        case .titleOnly: appString(localized: "privacy.titleOnly", defaultValue: "Titles only")
        case .hidden: appString(localized: "privacy.hiddenMode", defaultValue: "Hide contents")
        case .countOnly: appString(localized: "privacy.countOnly", defaultValue: "Counts only")
        }
    }

    var explanation: String {
        switch self {
        case .full:
            appString(localized: "privacy.fullDetail",
                defaultValue: "Your todos and memos appear in full on the Lock Screen."
            )
        case .titleOnly:
            appString(localized: "privacy.titleOnlyDetail",
                defaultValue: "Only titles appear. Open the app to read the rest."
            )
        case .hidden:
            appString(localized: "privacy.hiddenDetail",
                defaultValue: "Contents are replaced with a placeholder — useful if others can see your screen."
            )
        case .countOnly:
            appString(localized: "privacy.countOnlyDetail",
                defaultValue: "Only how many items remain is shown."
            )
        }
    }
}

enum LegalLinks {
    /// Unchanged from the Flutter build — the same URLs App Review has on file.
    static let privacyPolicy = URL(string: "https://motionfit.fit/locktodonote/privacy")!
    static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
}

enum AppInfo {
    static let reviewURL = URL(
        string: "https://apps.apple.com/app/id6783183501?action=write-review"
    )!

    static var versionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}
