import SwiftUI
import LockTodoNoteShared

/// The same rule editor is used by every capture surface and the todo editor.
struct AdvancedRepeatPicker: View {
    @Binding var rule: AdvancedRepeatRule?
    var startDate: Date
    var onApply: () -> Void = {}
    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { isPresented = true } label: {
                HStack {
                    Label("Smart Repeat · Pro", systemImage: "repeat")
                    Spacer()
                    Text(rule?.displayName ?? bilingualString(korean: "고급 반복", english: "Advanced repeat"))
                        .font(.caption)
                }
            }
            if let first = rule?.firstOccurrence(onOrAfter: startDate) {
                Text(bilingualString(korean: "첫 일정: ", english: "First occurrence: ")
                     + appDateString(first))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("smartRepeat.open")
        .sheet(isPresented: $isPresented) {
            AdvancedRepeatEditor(rule: rule, startDate: startDate) { value in
                rule = value
                onApply()
            }
        }
    }
}

private struct AdvancedRepeatEditor: View {
    let rule: AdvancedRepeatRule?
    let startDate: Date
    let apply: (AdvancedRepeatRule?) -> Void
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var days: Set<Int> = [2, 4, 6]
    @State private var weekday = 6
    @State private var interval = 3
    @State private var showPaywall = false

    private var draft: AdvancedRepeatRule {
        switch kind {
        case 1: .monthlyLastWeekday(weekday)
        case 2: .biweekly(weekday)
        case 3: .everyNDays(interval)
        default: .selectedWeekdays(days.sorted())
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(bilingualString(korean: "반복 조건", english: "Repeat rule"), selection: $kind) {
                        Text(bilingualString(korean: "요일 조합", english: "Selected weekdays")).tag(0)
                        Text(bilingualString(korean: "매월 마지막 요일", english: "Last weekday of each month")).tag(1)
                        Text(bilingualString(korean: "격주", english: "Every other week")).tag(2)
                        Text(bilingualString(korean: "N일 간격", english: "Every N days")).tag(3)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("smartRepeat.kind")
                    if kind == 0 {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Toggle(AdvancedRepeatRule.weekdayName(day), isOn: Binding(
                                get: { days.contains(day) },
                                set: { if $0 { days.insert(day) } else { days.remove(day) } }
                            ))
                        }
                    } else if kind == 3 {
                        Stepper(value: $interval, in: 2...365) {
                            Text(draft.displayName)
                        }
                    } else {
                        Picker(bilingualString(korean: "요일", english: "Weekday"), selection: $weekday) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                Text(AdvancedRepeatRule.weekdayName(day)).tag(day)
                            }
                        }
                        .accessibilityIdentifier("smartRepeat.weekday")
                    }
                } footer: {
                    if let first = draft.firstOccurrence(onOrAfter: startDate) {
                        Text(bilingualString(korean: "첫 일정: ", english: "First occurrence: ")
                             + appDateString(first))
                    }
                }
                Section {
                    Text(bilingualString(
                        korean: "매일·평일·매주 반복은 계속 무료입니다. 고급 반복의 신규 설정과 변경은 Pro에서 사용할 수 있습니다.",
                        english: "Daily, weekdays and weekly repeats stay free. Create and change advanced rules with Pro."
                    ))
                    .font(.footnote)
                    Button(bilingualString(korean: "고급 반복 해제", english: "Remove advanced repeat")) {
                        apply(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Smart Repeat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(purchases.isPro
                           ? appString(localized: "common.save", defaultValue: "Save")
                           : bilingualString(korean: "Pro로 사용", english: "Get Pro")) {
                        if purchases.isPro { apply(draft); dismiss() }
                        else { showPaywall = true }
                    }
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("smartRepeat.save")
                }
            }
        }
        .onAppear {
            switch rule {
            case .selectedWeekdays(let selected): kind = 0; days = Set(selected)
            case .monthlyLastWeekday(let day): kind = 1; weekday = day
            case .biweekly(let day): kind = 2; weekday = day
            case .everyNDays(let count): kind = 3; interval = count
            case nil: break
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(source: "smart_repeat") }
    }
}

extension AdvancedRepeatRule {
    static func weekdayName(_ day: Int) -> String {
        guard (1...7).contains(day) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = appLocale()
        return formatter.weekdaySymbols[day - 1]
    }

    var displayName: String {
        switch self {
        case .selectedWeekdays(let days):
            return days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map(Self.weekdayName).joined(separator: " · ")
        case .monthlyLastWeekday(let day):
            return bilingualString(korean: "매월 마지막 \(Self.weekdayName(day))", english: "Last \(Self.weekdayName(day)) each month")
        case .biweekly(let day):
            return bilingualString(korean: "격주 \(Self.weekdayName(day))", english: "Every other \(Self.weekdayName(day))")
        case .everyNDays(let count):
            return bilingualString(korean: "매 \(count)일마다", english: "Every \(count) days")
        }
    }
}
