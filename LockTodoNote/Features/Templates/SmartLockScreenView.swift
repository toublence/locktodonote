import SwiftUI
import LockTodoNoteShared

struct SmartLockScreenView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var schedules: SmartLockScreenStore
    @EnvironmentObject private var profiles: LayoutProfileStore
    @EnvironmentObject private var purchases: PurchaseService
    @State private var editingRule: SmartLockScreenRule?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Toggle(bilingualString(korean: "상황별 자동 전환", english: "Automatic switching"), isOn: Binding(
                    get: { schedules.schedule.isEnabled },
                    set: { value in
                        if value && !purchases.isPro { environment.requestPaywall(source: "smart_lock_screen"); return }
                        do { try schedules.setEnabled(value, isPro: purchases.isPro) }
                        catch { message = error.localizedDescription }
                    }
                ))
                .accessibilityIdentifier("schedule.enabled")
                Text(bilingualString(
                    korean: "예: 아침에는 개인 할 일, 업무 시간에는 업무 카드, 저녁에는 개인 일정. 시간대마다 저장 구성과 표시할 항목을 선택하세요. 규칙 밖에서는 수동 구성을 사용합니다.",
                    english: "Show personal tasks in the morning, work during office hours and personal plans in the evening. Choose a saved layout and content per time slot. Your manual layout applies outside these slots."
                )).font(.footnote)
                if !purchases.isPro {
                    Text(bilingualString(korean: "자동 전환은 Pro에서 동작합니다. 저장한 규칙은 유지됩니다.", english: "Automatic switching runs with Pro. Your saved rules are preserved."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(schedules.schedule.rules) { rule in
                    HStack {
                        Button { edit(rule) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.name)
                                Text((profiles.profiles.first { $0.id == rule.profileID }?.name ?? "—")
                                     + " · " + timeLabel(rule.startMinute) + "–" + timeLabel(rule.endMinute))
                                    .font(.caption)
                                Text(rule.weekdays.sorted().map(AdvancedRepeatRule.weekdayName).joined(separator: " · "))
                                    .font(.caption)
                                if !rule.isEnabled {
                                    Text(bilingualString(korean: "일시 중지", english: "Paused")).font(.caption)
                                }
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            do { try schedules.remove(rule) } catch { message = error.localizedDescription }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(appString(localized: "common.delete", defaultValue: "Delete"))
                    }
                }
                Button(bilingualString(korean: "전환 규칙 추가", english: "Add switching rule")) {
                    guard let profile = profiles.profiles.first else {
                        message = bilingualString(korean: "먼저 잠금화면 구성을 저장하세요.", english: "Save a Lock Screen layout first.")
                        return
                    }
                    edit(SmartLockScreenRule(name: "", profileID: profile.id, weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60))
                }
                .accessibilityIdentifier("schedule.add")
            }
            Section {
                Text(bilingualString(
                    korean: "기기의 현지 시간과 선택한 요일을 사용합니다. 종료 시각이 시작보다 빠르면 다음 날까지 이어집니다. 시간대가 겹치는 규칙은 저장할 수 없습니다.",
                    english: "Rules use the device’s local time. An earlier end time runs into the next day. Enabled time slots cannot overlap."
                ))
                Text(bilingualString(
                    korean: "위젯은 전환 시각을 미리 예약하지만 iOS에 따라 표시가 지연될 수 있습니다. Live Activity는 앱 실행 중 또는 허용된 백그라운드 실행 시 갱신합니다. 앱 종료 상태의 정확한 시각 전환은 보장되지 않습니다.",
                    english: "Widget transitions are prepared ahead of time; iOS may delay display. Live Activities update while the app runs or when iOS grants background execution. Exact transitions while the app is closed are not guaranteed."
                ))
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Smart Lock Screen")
        .disabled(schedules.loadFailed || profiles.loadFailed || !purchases.hasResolvedEntitlement)
        .overlay {
            if schedules.loadFailed || profiles.loadFailed {
                Text(SmartLockScreenStore.ScheduleError.unavailable.localizedDescription)
                    .padding().background(.regularMaterial)
            }
        }
        .sheet(item: $editingRule) { rule in SmartLockScreenRuleEditor(initial: rule) }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { message = nil }
        }
    }

    private func edit(_ rule: SmartLockScreenRule) {
        guard purchases.isPro else { environment.requestPaywall(source: "smart_lock_screen"); return }
        editingRule = rule
    }

    private func timeLabel(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

private struct SmartLockScreenRuleEditor: View {
    @EnvironmentObject private var schedules: SmartLockScreenStore
    @EnvironmentObject private var profiles: LayoutProfileStore
    @EnvironmentObject private var cards: CardStore
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var rule: SmartLockScreenRule
    @State private var message: String?

    init(initial: SmartLockScreenRule) { _rule = State(initialValue: initial) }

    private var todoChoices: [(id: String, text: String)] {
        var seen: Set<String> = []
        return cards.cards.flatMap(\.checklistItems).compactMap { item in
            seen.insert(item.effectiveRecurrenceId).inserted ? (item.effectiveRecurrenceId, item.text) : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(bilingualString(korean: "예: 업무 시간", english: "For example: Work hours"), text: $rule.name)
                        .accessibilityIdentifier("schedule.name")
                    Picker(bilingualString(korean: "저장 구성", english: "Saved layout"), selection: $rule.profileID) {
                        ForEach(profiles.profiles) { profile in Text(profile.name).tag(profile.id) }
                    }
                    Toggle(bilingualString(korean: "규칙 사용", english: "Enable rule"), isOn: $rule.isEnabled)
                    DatePicker(bilingualString(korean: "시작", english: "Start"), selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker(bilingualString(korean: "종료", english: "End"), selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Toggle(AdvancedRepeatRule.weekdayName(day), isOn: Binding(
                            get: { rule.weekdays.contains(day) },
                            set: { if $0 { rule.weekdays.append(day) } else { rule.weekdays.removeAll { $0 == day } } }
                        ))
                    }
                }
                Section(bilingualString(korean: "표시할 할 일", english: "Visible todos")) {
                    Toggle(bilingualString(korean: "모든 할 일", english: "All todos"), isOn: Binding(
                        get: { rule.todoSeriesIDs == nil }, set: { rule.todoSeriesIDs = $0 ? nil : [] }
                    ))
                    if rule.todoSeriesIDs != nil {
                        ForEach(todoChoices, id: \.id) { choice in
                            Toggle(choice.text, isOn: Binding(
                                get: { rule.todoSeriesIDs?.contains(choice.id) == true },
                                set: { selected in
                                    rule.todoSeriesIDs?.removeAll { $0 == choice.id }
                                    if selected { rule.todoSeriesIDs?.append(choice.id) }
                                }
                            ))
                        }
                        Text(bilingualString(korean: "선택한 반복 할 일은 이후 일정에도 적용됩니다. 새로 만든 다른 할 일은 이 목록에서 추가로 선택하세요.", english: "Selected repeating tasks include future occurrences. Select other newly created tasks here to include them."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(bilingualString(korean: "표시할 메모", english: "Visible notes")) {
                    Toggle(bilingualString(korean: "모든 메모", english: "All notes"), isOn: Binding(
                        get: { rule.memoCardIDs == nil }, set: { rule.memoCardIDs = $0 ? nil : [] }
                    ))
                    if rule.memoCardIDs != nil {
                        ForEach(cards.cards.filter { $0.type == .quickNote }) { card in
                            Toggle(card.title, isOn: Binding(
                                get: { rule.memoCardIDs?.contains(card.id) == true },
                                set: { selected in
                                    rule.memoCardIDs?.removeAll { $0 == card.id }
                                    if selected { rule.memoCardIDs?.append(card.id) }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle(bilingualString(korean: "전환 규칙", english: "Switching rule"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) {
                        do { try schedules.save(rule, isPro: purchases.isPro); dismiss() }
                        catch { message = error.localizedDescription }
                    }.disabled(!rule.isValid)
                    .accessibilityIdentifier("schedule.save")
                }
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { message = nil }
        }
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minute = start ? rule.startMinute : rule.endMinute
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let minute = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if start { rule.startMinute = minute } else { rule.endMinute = minute }
        })
    }
}
