import LockTodoNoteShared
import SwiftUI
import UIKit

struct AppleRemindersSettingsView: View {
    @EnvironmentObject private var sync: ReminderSyncService
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            #if DEBUG
            if DeviceQASupport.isEnabled && sync.isPro { DeviceQAReminderControls() }
            #endif
            Section {
                Text(bilingualString(
                    korean: "Apple 미리알림에 등록한 할 일을 잠금화면에 가져옵니다. 여기서 완료하면 미리알림에도 반영되어 두 번 입력할 필요가 없습니다.",
                    english: "Bring your Apple Reminders to the Lock Screen. Completing a task here also completes the original reminder, without entering it twice."
                ))
                if !sync.isPro {
                    Button(bilingualString(korean: "Pro로 미리알림 연결", english: "Connect Reminders with Pro")) {
                        environment.requestPaywall(source: "apple_reminders_sync")
                    }
                }
                if sync.isEnabled {
                    Toggle(
                        bilingualString(korean: "자동 동기화", english: "Automatic sync"),
                        isOn: Binding(get: { sync.isEnabled }, set: { enabled in
                            if !enabled { sync.disconnect() }
                        })
                    )
                    if !sync.isPro {
                        Text(bilingualString(
                            korean: "Pro가 만료되어 자동 동기화가 일시 중지되었습니다. 기존 기록은 유지됩니다.",
                            english: "Automatic sync is paused because Pro has expired. Existing items are preserved."
                        ))
                        .foregroundStyle(.secondary)
                    }
                } else if sync.isPro {
                    Button(bilingualString(korean: "미리알림 연결하고 동기화", english: "Connect and sync Reminders")) {
                        Task { await sync.connect() }
                    }
                    .disabled(sync.isSyncing || sync.isConnecting)
                    .accessibilityIdentifier("reminders.connect")
                }
            } footer: {
                Text(bilingualString(
                    korean: "연결하면 기본 목록을 먼저 가져옵니다. 아래에서 동기화할 목록을 변경할 수 있습니다. 연결을 끄면 이 앱의 가져온 항목만 제거하며 Apple 미리알림 원본은 유지합니다.",
                    english: "Connecting imports your default list first. Choose other lists below. Disconnecting removes only imported copies from this app and keeps the Apple originals."
                ))
            }

            if sync.hasAccess && sync.isEnabled {
                Section {
                    ForEach(sync.lists) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { sync.selectedListIDs.contains(list.id) },
                            set: { selected in Task { await sync.setList(list.id, selected: selected) } }
                        ))
                        .disabled(!sync.isPro || sync.isSyncing)
                    }
                    ForEach(sync.unavailableListIDs, id: \.self) { identifier in
                        Toggle(
                            bilingualString(korean: "사용할 수 없는 목록", english: "Unavailable list"),
                            isOn: Binding(
                                get: { sync.selectedListIDs.contains(identifier) },
                                set: { selected in Task { await sync.setList(identifier, selected: selected) } }
                            )
                        )
                        .disabled(!sync.isPro || sync.isSyncing)
                    }
                    if sync.lists.isEmpty {
                        Text(bilingualString(korean: "사용 가능한 목록이 없습니다.", english: "No lists are available."))
                    }
                } header: {
                    Text(bilingualString(korean: "동기화할 목록", english: "Lists to sync"))
                } footer: {
                    Text(bilingualString(
                        korean: "편집 가능한 목록만 표시합니다. 날짜가 없거나 기한이 지난 할 일은 오늘에 표시하고, 미래 할 일은 해당 날짜에 표시합니다. 제목·날짜·반복·삭제는 Apple 미리알림에서 변경해주세요.",
                        english: "Only writable lists are shown. Undated and overdue tasks appear today; future tasks appear on their due date. Edit titles, dates, recurrence, or delete tasks in Apple Reminders."
                    ))
                }
            }

            Section {
                if sync.isSyncing {
                    ProgressView(bilingualString(korean: "동기화 중", english: "Syncing"))
                }
                if let date = sync.lastSync {
                    LabeledContent(
                        bilingualString(korean: "마지막 동기화", english: "Last synced"),
                        value: date.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let error = sync.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                if !sync.hasAccess {
                    Button(bilingualString(korean: "iOS 접근 권한 설정", english: "Open iOS permission settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if sync.isEnabled && sync.isPro {
                    Button(bilingualString(korean: "지금 동기화", english: "Sync now")) {
                        Task { await sync.synchronize() }
                    }
                    .disabled(sync.isSyncing)
                }
            } footer: {
                Text(bilingualString(
                    korean: "앱 실행·복귀와 사용 중 미리알림 변경 시 자동 갱신합니다. 앱이 닫힌 동안에는 iOS가 허용한 백그라운드 새로고침 시 갱신하므로 즉시 반영이 보장되지는 않습니다. 잠금화면 완료는 원본에 바로 저장합니다.",
                    english: "Sync runs on launch, return to the app, and Reminders changes while running. With the app closed, iOS controls background refresh timing, so updates may be delayed. Lock Screen completion saves directly to the original."
                ))
            }
        }
        .navigationTitle(bilingualString(korean: "Apple 미리알림 연동", english: "Apple Reminders"))
        .task {
            sync.refreshLists()
            await sync.synchronize()
        }
    }
}
