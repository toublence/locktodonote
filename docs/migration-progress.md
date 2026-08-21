# SwiftUI 전환 진행 상황

원본 Flutter 프로젝트: `~/projects/glancecard` (**읽기만 함, 변경 없음**)
전환 대상: `~/projects/locktodonote`
전환 계획 근거: `~/projects/glancecard/docs/flutter-to-swiftui-migration-report.md`

**상태**: Phase 0–9 구현 완료. 남은 것은 실기기 QA와 아래 "사용자 결정 필요" 항목뿐이다.

규모: Swift 61개 파일, 약 13,100줄. 테스트 105개.

---

## 검증된 것

| 항목 | 방법 | 결과 |
|---|---|---|
| 공유 패키지 로직 | `swift test` 83개 | 통과 |
| 분석 이벤트 계약 | 앱 단위 테스트 11개 | 통과 |
| 주요 사용자 흐름 | UI 테스트 11개 | 통과 |
| 앱 + 확장 2개 빌드 | Debug/Release, 시뮬레이터·실기기 타깃 | 통과 |
| 데이터 저장·재시작 후 로드 | 시뮬레이터 + UI 테스트 | 통과 |
| Dart 호환 날짜 형식 기록 | `cards.json` 직접 확인 | 통과 |
| Live Activity 시작 | 시뮬레이터 실행 | 통과 |
| Dynamic Island 렌더링 | 홈 화면 확인 | 통과 |
| 온보딩 → 첫 카드 → 페이월 | 시뮬레이터 전체 흐름 | 통과 |
| 실제 App Store 상품 조회 | 페이월에 실가격 표시 | 통과 |
| 9개 언어 로컬라이제이션 | 번들 `.lproj` 9개 + ko 실행 확인 | 통과 |
| Firebase 초기화 | 시뮬레이터 로그 | 통과(경고 2건, 아래) |

### App Store에서 확인된 사실

시뮬레이터 페이월이 **실제 App Store Connect 데이터**를 가져왔다. 보고서 §15의 미확인 항목 일부가 해소된다.

- Monthly $0.99 / Yearly $4.99 / Lifetime $9.99 — 알려준 값과 일치
- **연간 상품에 7일 무료 체험이 이미 등록되어 있다.** 보고서 §8.11에서 "도입 권장"으로 적었으나 이미 존재했다
- 연간 절약률 58%가 자동 계산되어 표시됨
- 코드가 `yealy`/`yearly` 두 ID를 모두 조회하므로 어느 쪽이 실제 등록이든 동작한다

### Firebase 실행 로그에서 확인된 것

`Analytics v.12.18.0 started` / `Analytics collection enabled` — **정상 작동한다.** 다만 경고 3건이 남는다.

1. **`I-COR000003` "not yet been configured"** — `FirebaseApp.configure()` 호출 6ms 전에 SDK가 자동 초기화를 시도하며 남기는 경고다. configure를 앱 진입점(`LockTodoNoteApp.init()`)의 가장 이른 시점으로 옮겼는데도 남는다. SDK 내부 순서라 앱 코드로는 제거할 수 없고, 직후 Analytics가 정상 시작하므로 이벤트 유실은 없다.
2. **`I-COR000008` 번들 ID 불일치** — plist는 `fit.ttak.app`, 앱은 `com.namslab.glancecard`. **의도한 상태다.** 이 덕분에 이벤트가 Flutter 빌드와 같은 Firebase 앱 레코드로 들어가 대시보드가 이어진다. §15-1 결정 전까지 이대로 둔다.
3. **`I-ACS044003` IDFA 접근 불가** — `GoogleAppMeasurementIdentitySupport`가 링크되지 않았다. 광고 SDK가 없으니 실질적 영향은 없지만, **ATT 권한을 요청하면서 IDFA를 쓰지 못하는 상태**다. 보고서 §15-9(ATT 제거 검토)의 근거가 강해진다.

**아직 검증되지 않은 것**: 이벤트가 Firebase 서버에 실제 도착하는지. `-FIRAnalyticsDebugEnabled`가 `simctl launch` 인자로 전달되지 않아 시뮬레이터에서 확인하지 못했다. 앱 코드가 올바른 이름·파라미터로 보내는 것까지는 단위 테스트 11개로 고정했으므로, 남은 것은 **Firebase 콘솔 DebugView에서 실기기로 확인**하는 일이다.

---

## 완료된 단계

### Phase 1 — Shared 패키지 + 마이그레이션
`Packages/LockTodoNoteShared` — 모델, App Group 계층, 대시보드 합성, 마이그레이터.

**검증된 핵심 사실**
- `shared_preferences` 2.5.5는 모든 키에 `flutter.` 접두사를 붙인다(플러그인 소스로 확인). 앱은 `setPrefix`를 호출하지 않는다
- `setStringList` 미사용 → 리스트 인코딩 함정 없음
- Dart `toIso8601String()`은 마이크로초 6자리 + 타임존 없음 → 전용 파서로 해결하고 **쓰기도 같은 형식 유지**(롤백 호환)

**마이그레이션 안전장치**: 원본 `flutter.*` 키는 읽기 전용, 카드 수 검증 후에만 버전 커밋, 실패 시 재시도, 중복 실행 방지.

### Phase 2–4 — 앱 셸, Todo/Memo/캘린더, 템플릿
상단 세그먼트 내비게이션(오늘·캘린더·표시) + 설정 모달. 홈에서 템플릿을 가로 스크롤로 즉시 전환하고, 인라인 빠른 입력으로 할 일/메모를 바로 적는다. 7종 템플릿, Pro 게이트("탭 → 가치 안내 → 페이월"), PhotosPicker 이미지, D-Day 편집기.

### Phase 5 — ActivityKit / WidgetKit
`LiveActivityService` + `DashboardCoordinator`. **MethodChannel 브리지 완전 제거.** 확장이 Shared 패키지 타입을 직접 사용한다.

`GlanceDashboardAttributes` 타입 이름은 유지했다 — ActivityKit이 실행 중인 활동을 이 타입으로 식별하므로, 이름이 바뀌면 업데이트 전에 시작된 카드를 앱이 종료조차 할 수 없다.

### Phase 6 — App Intents / 단축어
공개 인텐트 2개 유지, Live Activity 버튼 인텐트 3종, dead stub 3종 제거. **단축어 카운터를 App Group 하나로 통합**(보고서 §4.7 버그 수정).

### Phase 7 — StoreKit 2 / 페이월
`Transaction.currentEntitlements` 기반, `Transaction.updates` 리스너 신규 추가, 복원, 24시간 트라이얼. 연간 기본 선택 + 절약 배지.
**미배선 훅 3종 배선**(보고서 §8.6·8.7): 첫 잠금화면 성공 페이월, 트라이얼 만료 페이월, 리뷰 요청.

### Phase 8 — Firebase / 분석
Firebase SDK(Analytics + Crashlytics) SPM 통합, dSYM 업로드 스크립트 포함. 이벤트 이름·파라미터는 Flutter 빌드와 동일하게 유지. 확장 이벤트 큐 드레인 시 `queued_delay_hours`를 붙여 지연 왜곡을 측정 가능하게 했다.
신규 이벤트: `pro_template_tapped`, `pro_info_sheet_viewed`, `migration_completed/failed`, `widget_setup_started/confirmed`, `widget_todo_completed`, `dynamic_island_interacted`, `settings_opened`, `top_destination_selected`.

### Phase 9 — 로컬라이제이션 / 링크 / 테스트
- **9개 언어 전량 번역**(en·ko·ja·es·hi·de·fr·zh-Hans·zh-Hant), 191키. 위젯 확장도 별도 카탈로그 19키 × 9언어로 통합
- **인앱 언어 변경**(`AppLanguageStore`): 시스템 + 9개 언어. 위젯도 App Group의 `app.languageOverride`를 읽어 함께 전환된다
- **링크 라이브러리**: Share Extension 큐를 소비하는 화면. 큐가 무한정 쌓이던 문제 해소
- `PrivacyInfo.xcprivacy` 작성
- 테스트 105개

---

## 확정한 식별 정보 (운영값 유지)

| 항목 | 값 |
|---|---|
| Bundle ID | `com.namslab.glancecard` |
| Widget | `com.namslab.glancecard.widget` |
| Share | `com.namslab.glancecard.ShareExtension` |
| App Group | `group.com.namslab.glancecard` |
| URL Scheme | `glancecard` |
| Team | `2CZQR7Q423` |
| 버전 | 1.2.0 (14) — 기존 1.1.3(13)보다 상위 |

---

## 전환 중 발견해 고친 결함

- **저장 실패가 조용히 무시됨**: 쓰기 실패 시 메모리에는 반영되어 성공처럼 보였다. `CardStore.storeError` + 경고 배너로 표면화
- **단축어 카운터 이중화**(§4.7): App Group 단일 카운터로 통합. 앱은 Extension이 센 결과를 신뢰하고 재검사하지 않는다
- **온보딩 첫 입력 필드에 자동 포커스 없음**: 질문을 던지고 답하려면 한 번 더 탭해야 했다
- **`onboarding_start` 중복 발신**: 한때 `onboarding_started`를 함께 보내 모든 시작이 두 번 집계됐다. `onboarding_complete`는 하나뿐이라 짝도 맞지 않았다. Flutter가 쓰던 `onboarding_start` 하나만 남겼다
- **Firebase configure 시점**: `@StateObject` 초기화까지 미뤄져 있었다. 앱 진입점 `init()`으로 옮겼다

---

## 사용자 결정이 필요한 항목

1. **최소 iOS 16.1** — 진행을 위해 내가 선택했다. 위젯 타깃이 이미 16.1이고 Live Activity(16.2+)가 핵심 가치라는 판단이지만, **기존 15.x 사용자가 업데이트를 받지 못하는 되돌리기 어려운 결정**이다. App Store Connect에서 실사용 분포를 확인해 달라. `project.yml`의 `deploymentTarget` 한 줄로 되돌릴 수 있다.
2. **Firebase 등록 불일치**(보고서 §15-1) — 현재는 연속성 우선으로 기존 plist를 그대로 쓴다. 정합성을 택하면 새 iOS 앱을 등록해야 하고 대시보드가 끊긴다.
3. **ATT 유지 여부**(보고서 §15-9) — 광고 SDK가 없고 IDFA도 링크되지 않은 상태에서 "맞춤형 광고" 문구로 권한을 요청 중이다. 제거를 권한다.
4. **가격 실험**(보고서 §8.13) — 7일 체험이 이미 있으므로 남은 선택지는 Lifetime 인상 등이다.

## 배포 전 남은 일 (실기기 필요)

- 실제 1.1.3 설치본 → 신버전 업데이트 마이그레이션(보고서 §5.4 절차)
- Sandbox 결제 및 **기존 구매 계정 복원**
- Firebase 콘솔 DebugView에서 이벤트 도착 확인
- 잠금화면 실물 확인, Dynamic Island 미지원 기기, iPad 레이아웃
- 단계적 출시 + Crashlytics 크래시율 게이트

---

## 빌드 방법

```bash
cd ~/projects/locktodonote && xcodegen generate
```

소스 파일을 추가·이동한 뒤 반드시 다시 실행한다(`.xcodeproj`는 생성물이라 git에서 제외).

```bash
cd ~/projects/locktodonote/Packages/LockTodoNoteShared && swift test
```

```bash
cd ~/projects/locktodonote && xcodebuild -project LockTodoNote.xcodeproj -scheme LockTodoNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```
