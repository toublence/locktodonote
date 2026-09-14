import SwiftUI

enum PrimaryDestination: String, CaseIterable, Hashable, Identifiable {
    case today
    case calendar
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: appString(localized: "navigation.today", defaultValue: "Today")
        case .calendar: appString(localized: "navigation.calendar", defaultValue: "Calendar")
        case .settings: appString(localized: "navigation.settings", defaultValue: "Settings")
        }
    }
}

struct AppShellView: View {
    @Binding var selection: PrimaryDestination

    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            TopControlLayer(selection: $selection)
                .id(languageStore.selection)

            Group {
                switch selection {
                case .today:
                    LockScreenTabView()
                case .calendar:
                    CalendarTabView()
                case .settings:
                    SettingsTabView()
                }
            }
            .id(languageStore.selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .onChange(of: selection) { destination in
            analytics.topDestinationSelected(destination: destination.rawValue)
            if destination == .today {
                dashboard.followToday()
                dashboard.publish()
            } else if destination == .settings {
                analytics.settingsOpened(source: "top_control")
            }
        }
    }
}

private struct TopControlLayer: View {
    @Binding var selection: PrimaryDestination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Picker(
            appString(localized: "navigation.primary", defaultValue: "Main menu"),
            selection: $selection
        ) {
            ForEach(PrimaryDestination.allCases) { destination in
                Text(destination.title)
                    .tag(destination)
                    .accessibilityIdentifier("navigation.\(destination.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(maxWidth: horizontalSizeClass == .regular ? 420 : 340)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
