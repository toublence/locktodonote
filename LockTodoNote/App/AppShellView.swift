import SwiftUI

enum PrimaryDestination: String, CaseIterable, Hashable, Identifiable {
    case today
    case calendar
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: appString(localized: "navigation.today", defaultValue: "Today")
        case .calendar: appString(localized: "navigation.calendar", defaultValue: "Calendar")
        case .display: appString(localized: "navigation.display", defaultValue: "Display")
        }
    }
}

struct AppShellView: View {
    @Binding var selection: PrimaryDestination
    @Binding var isSettingsPresented: Bool

    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TopControlLayer(
                    selection: $selection,
                    onOpenSettings: {
                        analytics.settingsOpened(source: "top_control")
                        isSettingsPresented = true
                    }
                )

                Group {
                    switch selection {
                    case .today:
                        LockScreenTabView()
                    case .calendar:
                        CalendarTabView()
                    case .display:
                        DisplayContinuityView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(palette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: selection) { destination in
            analytics.topDestinationSelected(destination: destination.rawValue)
            if destination == .today {
                dashboard.selectedDate = Date()
                dashboard.publish()
            }
        }
    }
}

private struct TopControlLayer: View {
    @Binding var selection: PrimaryDestination
    let onOpenSettings: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
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
            .frame(maxWidth: 420)

            settingsButton
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onOpenSettings) { settingsLabel }
                .buttonStyle(.glass)
        } else {
            Button(action: onOpenSettings) { settingsLabel }
                .buttonStyle(.bordered)
        }
    }

    private var settingsLabel: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .frame(width: 32, height: 32)
            .accessibilityLabel(appString(localized: "navigation.settings", defaultValue: "Settings"))
            .accessibilityIdentifier("navigation.settings")
    }
}
