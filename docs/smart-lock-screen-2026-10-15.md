# Smart Lock Screen 구현 — 2026-10-15

## 사용 방법

1. 기존 ‘저장한 잠금화면 구성’에서 개인·업무 등 필요한 구성을 저장한다.
2. 같은 화면의 `Smart Lock Screen · Pro`에서 규칙을 추가한다. 이름, 저장 구성, 요일, 시작·종료 시각, 표시할 할 일·메모를 설정한다.
3. ‘상황별 자동 전환’을 켠다. 예: 매일 06:00–09:00 개인, 평일 09:00–18:00 업무, 매일 18:00–23:00 개인.

구성에는 기존 템플릿·사진·텍스트 크기·D-Day 등 잠금화면 설정이 적용된다. 앱의 색상 테마 자체는 시간대에 따라 변경하지 않는다. 규칙이 없는 시간에는 사용자의 수동 구성으로 돌아간다. 자동 전환이 활성인 시간에는 수동으로 다른 구성을 적용해도 자동 규칙이 우선한다. 수동 구성을 즉시 사용하려면 자동 전환을 끈다.

## 규칙과 콘텐츠

- Pro 기능이며 최대 8개 규칙을 저장한다. 무료의 기존 구성 저장 1개 정책을 유지한다.
- 현지 시각과 요일을 사용하며 시작은 포함, 종료는 제외한다. 활성 규칙끼리 겹치면 저장을 차단한다. 종료가 시작보다 빠른 규칙은 다음 날까지 이어지고, 요일은 시작일 기준이다. 시작·종료 시각이 같으면 저장할 수 없다.
- 각 규칙은 할 일·메모를 모두 표시하거나 선택한 항목만 표시한다. 모두 표시 스위치를 끈 뒤 아무것도 선택하지 않으면 해당 종류의 항목을 표시하지 않는다.
- 반복 할 일은 시리즈 ID로 선택하므로 이후 생성되는 반복 항목에도 선택이 유지된다. 별도로 새로 만든 할 일은 사용자 선택 목록에 추가해야 한다. 앱의 원본 데이터와 완료 이력은 필터링으로 삭제되지 않는다.
- 활성 규칙은 오늘의 내용을 표시한다. 규칙 종료 후에는 기존 수동 날짜 선택을 사용한다.
- 사용 중인 저장 구성은 해당 규칙을 삭제하기 전까지 삭제할 수 없다. 구성 덮어쓰기는 다음 갱신부터 반영된다.
- 구독 만료 시 자동 전환을 중단하고 수동 구성을 사용한다. 규칙 데이터는 보존하며 자동 전환 끄기와 규칙 삭제는 무료에서도 가능하다.

## 갱신 경로

- 앱의 DashboardCoordinator에서 공유 규칙 해석기를 사용한다. 수동 설정을 자동 구성으로 덮어쓰지 않고 표시할 스냅샷만 합성한다. 저장 구성의 사진을 활성 설정 파일로 복사하거나 소유권을 변경하지 않는다.
- 앱 실행 중에는 다음 시간 경계에 갱신한다. 포그라운드 복귀, 주요 시각 변경, 구독·규칙·저장 구성 변경에도 재평가한다.
- 위젯은 규칙 경계, 자정, 캐시된 구독 만료 시각을 타임라인에 등록한다. 앱이 열려 있지 않아도 미리 생성한 시간별 항목을 사용할 수 있다. 타임라인은 최대 64개 항목으로 제한한다.
- 위젯의 시간별 스냅샷은 원본 카드와 대기 중인 입력·완료 요청을 읽어 합성하며 파일이나 처리 대기열을 변경하지 않는다. 아직 실제 저장되지 않은 반복·분리 카드의 항목은 앱으로 연결하여, 저장된 항목처럼 완료 요청을 보내지 않는다.
- 단축어 추가·새로고침과 위젯 완료 처리도 활성 규칙을 반영한다. 미리알림 동기화의 백그라운드 갱신 경로도 같은 해석기를 사용한다.
- Live Activity 갱신용 BGAppRefresh 요청을 등록한다. 기존 미리알림 동기화를 켜지 않아도 예약 요청을 생성한다.

## iOS 제한

WidgetKit 표시·갱신 시점과 BGAppRefresh 실행 시점은 iOS가 결정하므로 지연될 수 있다. ActivityKit의 Live Activity는 위젯 타임라인으로 내용이 바뀌는 방식이 아니다. 이번 구현의 Live Activity는 실행 중인 앱, 허용된 백그라운드 실행, 단축어 등의 갱신 경로를 사용한다. 앱이 종료되거나 실행 기회가 없는 상태에서 정각에 반드시 전환되는 기능으로 안내하거나 판매하면 안 된다. 이 제한은 설정 화면과 전용 결제 안내에도 표시했다. 원격 APNs 갱신 서버는 추가하지 않았다.

참고: [Apple ActivityKit](https://developer.apple.com/documentation/ActivityKit), [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

## 파일

- 공유 모델·스케줄 해석: `Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Dashboard/SmartLockScreenSchedule.swift`
- 규칙 저장: `LockTodoNote/Core/Storage/SmartLockScreenStore.swift`
- 실행 예약: `LockTodoNote/Core/Automation/SmartLockScreenService.swift`
- 설정 UI: `LockTodoNote/Features/Templates/SmartLockScreenView.swift`
- 연결: LayoutProfileStore, LayoutProfilesView, DashboardCoordinator, AppEnvironment, LockTodoNoteApp, ReminderSyncService, PaywallView, Info.plist
- 확장 연결: GlanceCardLockScreenWidget, GlanceCardAppIntents, GlanceCardLiveActivity
- 검증: `Packages/LockTodoNoteShared/Tests/LockTodoNoteSharedTests/SmartLockScreenScheduleTests.swift`

공유 App Group에 기존 `layout-profiles-v1.json` 형식을 유지하며 `smart-lock-screen-v1.json`을 별도 저장한다. 읽을 수 없는 규칙 파일을 빈 데이터로 덮어쓰지 않는다.

## 검증

요청한 저비용 검증 1회 내에서 수정된 앱·확장 Swift 파일 13개 구문 검사, Info.plist 백그라운드 식별자 확인, 공유 모듈 컴파일 및 신규 테스트 12개를 실행했고 모두 통과했다.

검증 항목: 시작·종료 경계, 아침/업무/저녁 선택, 자정과 주 경계 넘김, 겹침과 인접 시간대, 비활성·무료·없는 구성, 잘못된 입력, 반복 시리즈 콘텐츠 필터, 원본 보존과 필터 후 제목, JSON 호환, 타임라인 경계와 자정, DST 전환 후 현지 시간.

전체 앱/확장 빌드, StoreKit 구매, 기기별 UI, 실제 WidgetKit 표시 지연 및 BGAppRefresh 실행은 검증하지 않았다. 기존 전체 테스트 모음은 재실행하지 않았다.
