import SwiftUI
import LockTodoNoteShared

struct DisplayContinuityView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var liveActivity: LiveActivityService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.palette) private var palette

    @State private var selection: DisplayMode = .liveActivity
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 24 : 16) {
                modePicker
                detail
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
            .padding(.bottom, horizontalSizeClass == .regular ? 36 : 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .alert(
            errorMessage ?? "",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { errorMessage = nil }
        }
    }

    private var modePicker: some View {
        Picker(
            appString(localized: "display.deliveryMethod", defaultValue: "Delivery method"),
            selection: $selection
        ) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.shortTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selection) { analytics.displayModeSelected($0.rawValue) }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .liveActivity:
            liveActivityDetail
        case .widget:
            widgetDetail
        case .dynamicIsland:
            dynamicIslandDetail
        }
    }

    private var liveActivityDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailHeader(
                symbol: "rectangle.inset.filled.and.person.filled",
                title: DisplayMode.liveActivity.title,
                message: appString(localized: "display.live.description",
                    defaultValue: "See and complete today's items directly on the Lock Screen."
                )
            )

            VStack(spacing: 0) {
                statusRow(
                    title: appString(localized: "display.status", defaultValue: "Status"),
                    value: liveStatusTitle,
                    tint: liveStatusTint
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.template", defaultValue: "Template"),
                    value: settingsStore.settings.template.displayName
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.date", defaultValue: "Display date"),
                    value: dashboard.selectedDate.formatted(date: .abbreviated, time: .omitted)
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.lastUpdate", defaultValue: "Last update"),
                    value: dashboard.snapshot?.updatedAt.formatted(date: .omitted, time: .shortened)
                        ?? appString(localized: "display.notYet", defaultValue: "Not yet")
                )
            }
            .padding(.horizontal, 16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button {
                    Task { await startOrRestartLiveActivity() }
                } label: {
                    workingLabel(
                        liveActivity.state.isRunning
                            ? appString(localized: "display.restart", defaultValue: "Restart")
                            : appString(localized: "liveActivity.start", defaultValue: "Show on Lock Screen")
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || isUnsupported)

                if liveActivity.state.isRunning {
                    Button(role: .destructive) {
                        Task {
                            isWorking = true
                            await dashboard.stopLiveActivity()
                            analytics.liveActivityEnded()
                            isWorking = false
                        }
                    } label: {
                        Text(appString(localized: "display.end", defaultValue: "End"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }
            }
        }
    }

    private var widgetDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailHeader(
                symbol: "rectangle.grid.2x2",
                title: DisplayMode.widget.title,
                message: appString(localized: "display.widget.description",
                    defaultValue: "Your Today card remains available after a Live Activity ends."
                )
            )

            VStack(alignment: .leading, spacing: 14) {
                Label(
                    appString(localized: "display.widget.step1", defaultValue: "Touch and hold the Home Screen."),
                    systemImage: "1.circle.fill"
                )
                Label(
                    appString(localized: "display.widget.step2", defaultValue: "Tap Edit, then Add Widget."),
                    systemImage: "2.circle.fill"
                )
                Label(
                    appString(localized: "display.widget.step3", defaultValue: "Choose LockTodoNote and the medium size."),
                    systemImage: "3.circle.fill"
                )
            }
            .font(.subheadline)
            .foregroundStyle(palette.textPrimary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )

            Button {
                analytics.widgetSetupStarted()
                environment.appGroup.reloadWidgetTimelines()
                environment.appGroup.defaults?.set(
                    true,
                    forKey: FlutterPreferenceKeys.widgetInstallationHandled
                )
                environment.grantWidgetInstallRewardIfNeeded()
                analytics.widgetInstalledConfirmed()
            } label: {
                Text(appString(localized: "display.widget.confirm", defaultValue: "I added the Widget"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var dynamicIslandDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailHeader(
                symbol: "capsule.inset.filled",
                title: DisplayMode.dynamicIsland.title,
                message: appString(localized: "display.island.description",
                    defaultValue: "On supported iPhones, the current Live Activity automatically appears in Dynamic Island."
                )
            )

            VStack(alignment: .leading, spacing: 14) {
                previewLine(symbol: "checkmark.circle", title: "Compact", detail: remainingTodoText)
                Divider()
                previewLine(
                    symbol: "checkmark",
                    title: "Minimal",
                    detail: appString(localized: "display.island.minimal", defaultValue: "Remaining todo count")
                )
                Divider()
                previewLine(
                    symbol: "rectangle.expand.vertical",
                    title: "Expanded",
                    detail: appString(localized: "display.island.expanded", defaultValue: "Todos, memo, and completion actions")
                )
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )

            Text(
                appString(localized: "display.island.note",
                    defaultValue: "Dynamic Island follows the Live Activity. No separate setup is required."
                )
            )
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
        }
    }

    private func detailHeader(symbol: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(palette.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func statusRow(title: String, value: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(value).foregroundStyle(palette.textPrimary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 14)
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 20)
            Text(value)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 14)
    }

    private func previewLine(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func workingLabel(_ title: String) -> some View {
        Group {
            if isWorking {
                ProgressView()
            } else {
                Text(title).font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var liveStatusTitle: String {
        switch liveActivity.state {
        case .active: appString(localized: "display.active", defaultValue: "Active")
        case .possiblyExpired: appString(localized: "display.stale", defaultValue: "Stale")
        case .notStarted:
            hasStartedBefore
                ? appString(localized: "display.ended", defaultValue: "Ended")
                : appString(localized: "display.notStarted", defaultValue: "Not started")
        case .unsupported(let reason):
            reason == "disabled"
                ? appString(localized: "display.disabled", defaultValue: "Disabled")
                : appString(localized: "display.unsupported", defaultValue: "Unsupported")
        }
    }

    private var liveStatusTint: Color {
        switch liveActivity.state {
        case .active: palette.success
        case .possiblyExpired: palette.warning
        case .notStarted: palette.textTertiary
        case .unsupported: palette.danger
        }
    }

    private var isUnsupported: Bool {
        if case .unsupported = liveActivity.state { return true }
        return false
    }

    private var hasStartedBefore: Bool {
        environment.appGroup.defaults?.bool(forKey: FlutterPreferenceKeys.liveActivityStarted) ?? false
    }

    private var remainingTodoText: String {
        let count = dashboard.snapshot?.todoItems.filter { !$0.isDone }.count ?? 0
        return String(format: appString(localized: "display.island.remaining", defaultValue: "%d remaining"), count)
    }

    private func startOrRestartLiveActivity() async {
        let wasRunning = liveActivity.state.isRunning
        isWorking = true
        defer { isWorking = false }
        do {
            try await dashboard.startLiveActivity()
            let snapshot = dashboard.currentSnapshot()
            analytics.liveActivityStarted(
                taskCount: snapshot.totalCount,
                remainingCount: snapshot.remainingCount,
                hasMemo: !snapshot.memoItems.isEmpty,
                templateId: snapshot.lockScreenLayout,
                source: "display"
            )
            if wasRunning { analytics.liveActivityRestarted() }
        } catch let error as LiveActivityService.LiveActivityError {
            analytics.liveActivityStartFailed(
                reason: error.analyticsReason,
                templateId: settingsStore.settings.template.rawValue
            )
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DisplayMode: String, CaseIterable, Identifiable {
    case liveActivity
    case widget
    case dynamicIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveActivity: "Live Activity"
        case .widget: "Home Widget"
        case .dynamicIsland: "Dynamic Island"
        }
    }

    var shortTitle: String {
        switch self {
        case .liveActivity: "Live"
        case .widget: "Widget"
        case .dynamicIsland: "Island"
        }
    }

    var symbol: String {
        switch self {
        case .liveActivity: "rectangle.inset.filled.and.person.filled"
        case .widget: "rectangle.grid.2x2"
        case .dynamicIsland: "capsule.inset.filled"
        }
    }

    var summary: String {
        switch self {
        case .liveActivity:
            appString(localized: "display.live.summary", defaultValue: "Current Lock Screen card")
        case .widget:
            appString(localized: "display.widget.summary", defaultValue: "Continues after Live ends")
        case .dynamicIsland:
            appString(localized: "display.island.summary", defaultValue: "Compact activity controls")
        }
    }
}
