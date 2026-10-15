# Apple 미리알림 연동 구현

작성일 2026년 10월 15일

설정의 Apple 미리알림 연동에서 Pro 사용자가 연결하고 동기화할 목록을 선택한다. 처음 연결하면 편집 가능한 기본 목록을 가져온다.

## 동작 범위

- Apple 미리알림의 미완료 항목을 가져오며, 기한이 없거나 지난 항목은 오늘에 표시한다. 미래 항목은 해당 날짜에 표시한다.
- 원본의 제목·기한·완료·완료 취소·삭제·목록 이동을 다음 동기화에 반영한다. 처음 연결할 때 과거의 완료 항목 전체를 가져오지 않는다.
- 앱과 잠금화면에서 완료하면 EventKit 원본에 먼저 저장한다. 앱에서는 완료 취소도 원본에 저장한다. 원본 저장 실패 시 완료 처리하지 않는다.
- 제목·날짜·반복·삭제는 Apple 미리알림에서 관리한다. 가져온 항목의 수정·삭제 버튼은 일반 할 일과 구분했다.
- Apple의 반복 규칙을 앱의 반복 항목으로 복제하지 않는다. 원본에서 만들어지는 다음 항목을 다시 가져온다.
- 연결을 끄거나 목록 선택을 해제하면 해당 복사본만 제거한다. Apple 원본과 일반 LockTodoNote 기록은 삭제하지 않는다.
- Pro 만료 시 자동 동기화를 중지하고 기존 복사본을 보존한다.

## 자동 갱신 시점

앱 실행과 복귀, 실행 중 EventKit 변경 알림, iOS가 허용한 백그라운드 새로고침에서 갱신한다. 잠금화면 완료 저장에는 다음 앱 실행을 기다리지 않는다.

백그라운드 요청의 최초 실행 가능 시각은 15분 뒤로 설정했다. 이는 15분 주기 실행 약속이 아니다. iOS의 새로고침 허용 여부와 실행 시점, 강제 종료 및 전원 상태에 따라 갱신이 지연될 수 있다. 닫힌 앱을 계속 실행하거나 Live Activity 수명 제한을 우회하지 않는다.

## 주요 파일

- [목록과 권한 및 원본 완료 저장](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Models/AppleRemindersClient.swift)
- [안정적인 식별자와 복사본 병합](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Models/AppleReminderMirror.swift)
- [자동 및 백그라운드 동기화](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Reminders/ReminderSyncService.swift)
- [설정 화면](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Settings/AppleRemindersSettingsView.swift)
- [잠금화면 완료 처리](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift)
- [병합 로직 테스트](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Tests/LockTodoNoteSharedTests/AppleReminderMirrorTests.swift)

## 권한과 데이터

iOS 17 이상은 전체 미리알림 접근 요청을 사용하고 이전 OS는 기존 접근 API를 사용한다. 앱과 위젯에 권한 설명을 추가하고 10개 언어로 설명을 제공했다. 권한 요청은 앱 설정에서 사용자가 연결할 때만 표시한다.

조회 실패나 선택 목록 접근 오류는 정상적인 빈 목록으로 처리하지 않는다. 기존 파일 읽기 실패 시 가져온 항목만으로 파일을 덮어쓰지 않는다. 가져온 식별자는 앱 내부 연결에만 사용하며 원본 제목과 목록 이름을 분석 서버에 보내는 코드는 추가하지 않았다.

## 검증 범위

공유 모듈 컴파일과 새 동기화 서비스·설정 화면의 Swift 6 타입 검사를 통과했다. 타입 검사는 주변 앱 의존성 일부를 검증용 대체 타입으로 제공했으며 전체 앱 빌드는 아니다. 기존 앱 연결부는 구문 검사를 통과했고, 권한 plist와 10개 언어의 설명 파일도 확인했다. XcodeGen으로 새 소스와 프레임워크 연결을 반영했다.

식별자 구분, 중복 방지, 원본 변경과 완료 취소, 일반 기록 보존, 날짜 배치, 과거 완료 항목 제외를 다루는 테스트 6개를 추가했다. 단위 테스트 실행과 전체 앱 빌드, 실기기의 실제 권한·iCloud 반영·잠금화면 버튼·백그라운드 실행은 아직 수행하지 않았다.

API 근거는 [Apple EventKit 접근](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [미리알림 조회](https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders), [백그라운드 갱신](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)이다.
