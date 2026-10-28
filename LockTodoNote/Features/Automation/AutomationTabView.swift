import SwiftUI
import LockTodoNoteShared

struct AutomationTabView: View {
    @EnvironmentObject private var cards: CardStore
    @EnvironmentObject private var schedules: SmartLockScreenStore
    @EnvironmentObject private var profiles: LayoutProfileStore
    @EnvironmentObject private var sync: ReminderSyncService
    @EnvironmentObject private var purchases: PurchaseService
    @State private var editingTodo: TodoEntry?
    @State private var addingRepeat = false

    // Use one stored occurrence per series; imported reminders are managed by Apple.
    private var repeatingTodos: [TodoEntry] {
        var entries: [String: TodoEntry] = [:]
        for card in cards.cards.sorted(by: { $0.day() < $1.day() })
        where AppleReminderMirror.reminderID(from: card.id) == nil {
            for item in card.checklistItems where item.hasRecurrence {
                entries[item.effectiveRecurrenceId] = TodoEntry(card: card, item: item)
            }
        }
        return entries.values.sorted { $0.item.text.localizedStandardCompare($1.item.text) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(bilingualString(
                        korean: "반복 일정과 잠금화면 전환, 미리알림 연결을 한곳에서 관리하세요.",
                        english: "Manage repeating tasks, Lock Screen switching and Reminders in one place."
                    ))
                    .foregroundStyle(.secondary)
                }

                Section {
                    if let error = cards.storeError {
                        Text(error.detail).foregroundStyle(.red)
                    }
                    ForEach(repeatingTodos) { entry in
                        Button { editingTodo = entry } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.item.text).foregroundStyle(.primary)
                                    Spacer()
                                    accessBadge(pro: entry.item.advancedRepeat != nil)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.item.advancedRepeat?.displayName ?? entry.item.recurrence.displayName)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let next = nextOccurrence(for: entry) {
                                    Text(bilingualString(korean: "다음 일정: ", english: "Next date: ") + appDateString(next))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("automation.repeat.\(entry.item.effectiveRecurrenceId)")
                    }
                    if repeatingTodos.isEmpty {
                        Text(bilingualString(korean: "아직 반복 할 일이 없습니다.", english: "No repeating tasks yet."))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        addingRepeat = true
                    } label: {
                        Label(bilingualString(korean: "반복 할 일 추가", english: "Add repeating task"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("automation.addRepeat")
                } header: {
                    Text(bilingualString(korean: "반복 할 일", english: "Repeating tasks"))
                } footer: {
                    Text(bilingualString(
                        korean: "할 일을 눌러 반복을 수정하거나 ‘반복 없음’으로 중지하세요. 매일·평일·매주는 무료, 고급 반복은 Pro입니다.",
                        english: "Tap a task to edit its repeat or choose None to stop it. Daily, weekdays and weekly are free; advanced repeats require Pro."
                    ))
                }

                Section(bilingualString(korean: "잠금화면 자동 전환", english: "Lock Screen switching")) {
                    NavigationLink {
                        SmartLockScreenView().modifier(ShellBackButtonModifier())
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            featureLabel(bilingualString(korean: "상황별 카드 전환", english: "Scheduled card switching"), icon: "clock.arrow.2.circlepath", pro: true)
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(switchingStatus(at: context.date))
                                    if let next = nextSwitch(at: context.date) { Text(next) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("automation.smartLockScreen")
                    NavigationLink {
                        LayoutProfilesView().modifier(ShellBackButtonModifier())
                    } label: {
                        featureLabel(bilingualString(korean: "저장한 잠금화면 구성", english: "Saved layouts"), icon: "rectangle.stack", pro: false)
                    }
                }

                Section(bilingualString(korean: "연결과 빠른 추가", english: "Connections & Quick Add")) {
                    NavigationLink {
                        AppleRemindersSettingsView().modifier(ShellBackButtonModifier())
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            featureLabel(bilingualString(korean: "Apple 미리알림 연동", english: "Apple Reminders"), icon: "checklist", pro: true)
                            Text(remindersStatus).font(.caption).foregroundStyle(.secondary)
                            if let date = sync.lastSync {
                                Text(bilingualString(korean: "마지막 동기화: ", english: "Last synced: ") + date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("automation.appleReminders")
                    NavigationLink {
                        ShortcutsSettingsView().modifier(ShellBackButtonModifier())
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            featureLabel(bilingualString(korean: "단축어 & 빠른 추가", english: "Shortcuts & Quick Add"), icon: "bolt.badge.automatic", pro: false)
                            Text(bilingualString(korean: "문장에서 날짜 인식 · 무제한 단축어는 Pro", english: "Recognize dates in text · Unlimited Shortcuts with Pro"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("automation.shortcuts")
                }
            }
            .accessibilityIdentifier("automation.root")
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $editingTodo) { entry in TodoEditorSheet(entry: entry) }
        .sheet(isPresented: $addingRepeat) {
            QuickAddSheet(mode: .todo, source: "automation", initialRecurrence: .daily)
        }
    }

    private var remindersStatus: String {
        if let error = sync.errorMessage { return error }
        if sync.isSyncing { return bilingualString(korean: "동기화 중", english: "Syncing") }
        if !sync.isEnabled { return bilingualString(korean: "연결 안 됨", english: "Not connected") }
        if !sync.hasAccess { return bilingualString(korean: "미리알림 접근 권한 필요", english: "Reminders permission required") }
        if !purchases.isPro { return bilingualString(korean: "Pro 만료로 일시 중지", english: "Paused: Pro required") }
        return bilingualString(korean: "연결됨 · 선택한 목록 ", english: "Connected · Selected lists: ") + String(sync.selectedListIDs.count)
    }

    private func switchingStatus(at date: Date) -> String {
        if schedules.loadFailed || profiles.loadFailed {
            return bilingualString(korean: "저장된 규칙을 읽을 수 없습니다.", english: "Saved rules could not be read.")
        }
        guard purchases.isPro, schedules.schedule.isEnabled else {
            return bilingualString(korean: "자동 전환 꺼짐 · 수동 구성 사용", english: "Switching off · Using manual layout")
        }
        if let rule = schedules.schedule.activeRule(at: date, isPro: purchases.isPro, profiles: profiles.profiles),
           let profile = profiles.profiles.first(where: { $0.id == rule.profileID }) {
            return bilingualString(korean: "현재: ", english: "Current: ") + profile.name + " · " + rule.name
        }
        return bilingualString(korean: "현재 수동 구성 · 활성 규칙 ", english: "Manual layout · Enabled rules: ")
            + String(schedules.schedule.rules.filter(\.isEnabled).count)
    }

    private func nextOccurrence(for entry: TodoEntry) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let seed = entry.item.recurrenceAnchorDate ?? entry.card.day()
        let completedToday = cards.cards.contains { card in
            calendar.isDate(card.day(), inSameDayAs: today) && card.checklistItems.contains {
                $0.effectiveRecurrenceId == entry.item.effectiveRecurrenceId && $0.isDone
            }
        }
        let start = max(today, calendar.startOfDay(for: seed))
        for offset in 0...366 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.isDate(day, inSameDayAs: today) && completedToday { continue }
            if entry.item.isRecurrenceDue(seedDate: seed, on: day, calendar: calendar) { return day }
        }
        return nil
    }

    private func nextSwitch(at date: Date) -> String? {
        guard purchases.isPro, schedules.schedule.isEnabled,
              !schedules.loadFailed, !profiles.loadFailed else { return nil }
        let schedule = schedules.schedule
        let currentID = schedule.activeRule(at: date, isPro: true, profiles: profiles.profiles)?.id
        for boundary in schedule.transitionDates(after: date, days: 8) {
            let next = schedule.activeRule(at: boundary, isPro: true, profiles: profiles.profiles)
            guard next?.id != currentID else { continue }
            let name = next?.name ?? bilingualString(korean: "수동 구성", english: "Manual layout")
            return bilingualString(korean: "다음: ", english: "Next: ")
                + boundary.formatted(date: .abbreviated, time: .shortened) + " · " + name
        }
        return nil
    }

    private func featureLabel(_ title: String, icon: String, pro: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            accessBadge(pro: pro)
        }
    }

    private func accessBadge(pro: Bool) -> some View {
        Text(pro ? "Pro" : bilingualString(korean: "무료", english: "Free"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
