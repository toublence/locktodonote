import SwiftUI
import UIKit

enum PrimaryDestination: String, CaseIterable, Hashable, Identifiable {
    case today
    case calendar
    case automation
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: appString(localized: "navigation.today", defaultValue: "Today")
        case .calendar: appString(localized: "navigation.calendar", defaultValue: "Calendar")
        case .automation: bilingualString(korean: "자동화", english: "Automations")
        case .settings: appString(localized: "navigation.settings", defaultValue: "Settings")
        }
    }
}

struct AppShellView: View {
    @Binding var selection: PrimaryDestination
    @State private var lastContentDestination: PrimaryDestination = .today
    @State private var backAction: ShellBackAction?

    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            TopControlLayer(
                selection: $selection,
                canGoBack: selection == .settings || backAction != nil,
                contentSelection: Binding(
                    get: { selection == .settings ? nil : selection },
                    set: { if let destination = $0 { selection = destination } }
                ),
                onBack: {
                    if let backAction {
                        backAction.perform()
                    } else {
                        selection = lastContentDestination
                    }
                }
            )
                .id(languageStore.selection)

            Group {
                switch selection {
                case .today:
                    LockScreenTabView()
                case .calendar:
                    CalendarTabView()
                case .automation:
                    AutomationTabView()
                case .settings:
                    SettingsTabView()
                }
            }
            .id(languageStore.selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .onPreferenceChange(ShellBackActionPreferenceKey.self) { backAction = $0 }
        .onChange(of: selection) { destination in
            if destination != .settings { lastContentDestination = destination }
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
    let canGoBack: Bool
    @Binding var contentSelection: PrimaryDestination?
    let onBack: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if canGoBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bilingualString(korean: "뒤로", english: "Back"))
                } else {
                    Color.clear
                }
            }
            .frame(width: 44, height: 44)

            Spacer(minLength: 0)

            Picker(
                appString(localized: "navigation.primary", defaultValue: "Main menu"),
                selection: $contentSelection
            ) {
                ForEach([PrimaryDestination.today, .calendar, .automation]) { destination in
                    Text(destination.title)
                        .tag(Optional(destination))
                        .accessibilityIdentifier("navigation.\(destination.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(maxWidth: horizontalSizeClass == .regular ? 380 : 280)

            Spacer(minLength: 0)

            Button { selection = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appString(localized: "navigation.settings", defaultValue: "Settings"))
            .accessibilityIdentifier("navigation.settings")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

struct ShellBackAction: Equatable, Sendable {
    let id: UUID
    let perform: @MainActor @Sendable () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct ShellBackActionPreferenceKey: PreferenceKey {
    static let defaultValue: ShellBackAction? = nil

    static func reduce(value: inout ShellBackAction?, nextValue: () -> ShellBackAction?) {
        if let next = nextValue() { value = next }
    }
}

struct ShellBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let dismiss = dismiss
        return content
            .navigationBarBackButtonHidden(true)
            .preference(key: ShellBackActionPreferenceKey.self, value: ShellBackAction(id: id, perform: { dismiss() }))
    }
}
