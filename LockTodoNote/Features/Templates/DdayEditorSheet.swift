import SwiftUI
import LockTodoNoteShared

/// Edits the D-Day slot shown by the D-Day template.
struct DdayEditorSheet: View {
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var memo = ""
    @State private var targetDate = Date()
    @State private var hasTarget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        appString(localized: "dday.titleField", defaultValue: "What are you counting down to?"),
                        text: $title
                    )
                }

                Section {
                    Toggle(
                        appString(localized: "dday.setDate", defaultValue: "Set a date"),
                        isOn: $hasTarget.animation()
                    )
                    if hasTarget {
                        DatePicker(
                            appString(localized: "dday.date", defaultValue: "Date"),
                            selection: $targetDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                } footer: {
                    if hasTarget, let text = dashboard.composer.ddayText(targetDate) {
                        Text(
                            String(
                                format: appString(localized: "dday.preview", defaultValue: "Shows as %@"),
                                text
                            )
                        )
                    }
                }

                Section(appString(localized: "dday.memo", defaultValue: "Note")) {
                    TextField(
                        appString(localized: "dday.memoField", defaultValue: "Optional note"),
                        text: $memo,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                }
            }
            .navigationTitle(appString(localized: "dday.edit", defaultValue: "D-Day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
                }
            }
        }
        .onAppear {
            let settings = settingsStore.settings
            title = settings.ddayTitle ?? ""
            memo = settings.ddayMemo ?? ""
            hasTarget = settings.ddayTargetDate != nil
            targetDate = settings.ddayTargetDate ?? Date()
        }
    }

    private func save() {
        settingsStore.settings.ddayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.ddayMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.settings.ddayTargetDate = hasTarget ? targetDate : nil
        if hasTarget { analytics.ddaySet() }
        dashboard.publish()
        dismiss()
    }
}
