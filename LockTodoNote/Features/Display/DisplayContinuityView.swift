import SwiftUI
import UIKit
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
    @State private var widgetMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 24 : 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appString(localized: "display.continuity.title", defaultValue: "One card, across three places"))
                        .font(.title2.bold())
                        .foregroundStyle(palette.textPrimary)
                    Text(
                        appString(
                            localized: "display.continuity.detail",
                            defaultValue: "When Live Activity ends, continue your day in the Widget."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                }
                modePicker
                detail
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
            .padding(.bottom, horizontalSizeClass == .regular ? 36 : 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
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

            DashboardPreviewCard(snapshot: dashboard.currentSnapshot())

            VStack(spacing: 0) {
                statusRow(
                    title: appString(localized: "display.status", defaultValue: "Status"),
                    value: liveStatusTitle,
                    tint: liveStatusTint
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.remainingTime", defaultValue: "Time remaining"),
                    value: remainingActivityText
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.template", defaultValue: "Template"),
                    value: settingsStore.settings.template.displayName
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.items", defaultValue: "Displayed items"),
                    value: displayedItemSummary
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.widgetFallback", defaultValue: "Widget fallback"),
                    value: appString(localized: "display.ready", defaultValue: "Ready")
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.date", defaultValue: "Display date"),
                    value: appDateString(dashboard.selectedDate)
                )
                Divider()
                valueRow(
                    title: appString(localized: "display.lastUpdate", defaultValue: "Last update"),
                    value: dashboard.snapshot.map {
                        appDateString($0.updatedAt, dateStyle: .none, timeStyle: .short)
                    }
                        ?? appString(localized: "display.notYet", defaultValue: "Not yet")
                )
            }
            .padding(.horizontal, 16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )

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

            WidgetPreviewCard(snapshot: dashboard.currentSnapshot())

            Label(
                environment.isWidgetInstalled
                    ? appString(localized: "display.widget.installed", defaultValue: "Widget installed")
                    : appString(localized: "display.widget.notVerified", defaultValue: "Widget installation not verified"),
                systemImage: environment.isWidgetInstalled ? "checkmark.circle.fill" : "circle.dashed"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(environment.isWidgetInstalled ? palette.accent : palette.textSecondary)

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
                let alreadySelfReported = environment.appGroup.defaults?.bool(
                    forKey: AppGroupKeys.widgetConfirmationPending
                ) ?? false
                environment.appGroup.defaults?.set(
                    true,
                    forKey: AppGroupKeys.widgetConfirmationPending
                )
                environment.appGroup.reloadWidgetTimelines()
                Task {
                    let installed = await environment.verifyWidgetInstallation()
                    if !installed, !alreadySelfReported {
                        analytics.widgetInstalledConfirmed(method: "self_report")
                    }
                    widgetMessage = installed
                        ? appString(localized: "display.widget.verified", defaultValue: "Widget installation verified.")
                        : appString(localized: "display.widget.verifyFailed", defaultValue: "We couldn't find the widget yet. Add it, then try again.")
                }
            } label: {
                Text(appString(localized: "display.widget.confirm", defaultValue: "I added the Widget"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            analytics.widgetSetupStarted()
            Task { _ = await environment.verifyWidgetInstallation() }
        }
        .alert(
            widgetMessage ?? "",
            isPresented: Binding(
                get: { widgetMessage != nil },
                set: { if !$0 { widgetMessage = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { widgetMessage = nil }
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

            if !DynamicIslandSupport.isAvailable {
                Text(
                    appString(
                        localized: "display.island.unavailableDevice",
                        defaultValue: "Dynamic Island is not available on this device. On supported iPhones it appears automatically with Live Activity."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {

            HStack(spacing: 12) {
                islandPreview(symbol: "checkmark.circle.fill", text: "\(dashboard.currentSnapshot().remainingCount)")
                islandPreview(symbol: nil, text: "\(dashboard.currentSnapshot().remainingCount)")
                islandPreview(symbol: "checkmark.circle", text: remainingTodoText, expanded: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                previewLine(
                    symbol: "checkmark.circle",
                    title: appString(localized: "display.island.compactTitle", defaultValue: "Small display"),
                    detail: appString(localized: "display.island.compactDetail", defaultValue: "Shows the remaining todo count at a glance.")
                )
                Divider()
                previewLine(
                    symbol: "checkmark",
                    title: appString(localized: "display.island.minimalTitle", defaultValue: "Separated display"),
                    detail: appString(localized: "display.island.minimal", defaultValue: "Used alongside another Live Activity.")
                )
                Divider()
                previewLine(
                    symbol: "rectangle.expand.vertical",
                    title: appString(localized: "display.island.expandedTitle", defaultValue: "When pressed and held"),
                    detail: appString(localized: "display.island.expanded", defaultValue: "Review and complete todos and memos.")
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

    private func islandPreview(
        symbol: String?,
        text: String,
        expanded: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text).lineLimit(1)
        }
        .font(expanded ? .caption.weight(.semibold) : .subheadline.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, expanded ? 12 : 10)
        .frame(minWidth: expanded ? 130 : 52, minHeight: 42)
        .background(Color.black, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var liveStatusTitle: String {
        switch liveActivity.state {
        case .active: appString(localized: "display.active", defaultValue: "Active")
        case .possiblyExpired: appString(localized: "display.stale", defaultValue: "Stale")
        case .ended, .missing: appString(localized: "liveActivity.ended", defaultValue: "Ended")
        case .dismissed: appString(localized: "liveActivity.ended", defaultValue: "Stopped")
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
        case .possiblyExpired, .ended, .missing: palette.warning
        case .notStarted, .dismissed: palette.textTertiary
        case .unsupported: palette.danger
        }
    }

    private var hasStartedBefore: Bool {
        environment.appGroup.defaults?.bool(forKey: FlutterPreferenceKeys.liveActivityStarted) ?? false
    }

    private var remainingTodoText: String {
        let count = dashboard.snapshot?.todoItems.filter { !$0.isDone }.count ?? 0
        return String(format: appString(localized: "display.island.remaining", defaultValue: "%d remaining"), count)
    }

    private var displayedItemSummary: String {
        let snapshot = dashboard.currentSnapshot()
        return String(
            format: appString(localized: "calendar.itemSummary", defaultValue: "%d todos · %d memos"),
            snapshot.todoItems.count,
            snapshot.memoItems.count
        )
    }

    private var remainingActivityText: String {
        guard case .active(let startedAt) = liveActivity.state else {
            return appString(localized: "display.notApplicable", defaultValue: "—")
        }
        let seconds = max(0, Int(LiveActivityService.activityDuration - Date().timeIntervalSince(startedAt)))
        return String(
            format: appString(localized: "liveActivity.hoursMinutesLeft", defaultValue: "%dh %dm left"),
            seconds / 3600,
            (seconds % 3600) / 60
        )
    }

}

private struct WidgetPreviewCard: View {
    let snapshot: DashboardSnapshot

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.calendarTitle ?? snapshot.selectedDateText ?? "")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            ForEach(snapshot.todoItems.filter { !$0.isDone }.prefix(3), id: \.id) { todo in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .foregroundStyle(palette.accent)
                    Text(todo.text)
                        .lineLimit(1)
                        .foregroundStyle(palette.textPrimary)
                }
                .font(.subheadline)
            }

            if snapshot.todoItems.isEmpty {
                Text(appString(localized: "home.noTodos", defaultValue: "No todos yet"))
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            }

            if !snapshot.memoItems.isEmpty {
                Text(
                    String(
                        format: appString(localized: "display.memoCount", defaultValue: "%d memos"),
                        snapshot.memoItems.count
                    )
                )
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: 420, minHeight: 170, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appString(localized: "display.widget.preview", defaultValue: "Current medium Widget preview"))
    }
}

@MainActor
private enum DynamicIslandSupport {
    static var isAvailable: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.isKeyWindow {
                return window.safeAreaInsets.top >= 51
            }
        }
        return false
    }
}

private enum DisplayMode: String, CaseIterable, Identifiable {
    case liveActivity
    case widget
    case dynamicIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveActivity: appString(localized: "display.live.title", defaultValue: "Live Activity")
        case .widget: appString(localized: "display.widget.title", defaultValue: "Home Widget")
        case .dynamicIsland: appString(localized: "display.island.title", defaultValue: "Dynamic Island")
        }
    }

    var shortTitle: String {
        switch self {
        case .liveActivity: appString(localized: "display.live.short", defaultValue: "Live")
        case .widget: appString(localized: "display.widget.short", defaultValue: "Widget")
        case .dynamicIsland: appString(localized: "display.island.short", defaultValue: "Island")
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
