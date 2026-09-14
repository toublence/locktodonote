# LockTodoNote 구독률 저조 원인 분석 보고서

분석일: 2026-09-11
분석 대상: `main` @ cb81515, MARKETING_VERSION 1.1.4 (build 14)
분석 범위: 코드 전수 + 제공된 GA4 이벤트 요약 (총 사용자 77명, 총 이벤트 5,925, 총 수익 $7.00)
문서 상태: **ANALYSIS ONLY — 코드 변경 없음**

## 근거 표기

- **[C]** 코드에서 직접 확인 (파일:라인 표기)
- **[A]** 제공된 GA4 이벤트 데이터에서 확인
- **[D]** `docs/competitor-analysis-live-note-live-memo.md`에서 확인
- **[I]** 위 사실을 근거로 한 판단
- **가능성** 확정 불가, 추론

---

## 1. Executive Summary

### 결제율이 낮은 가장 큰 이유 5개

**1. Pro Preview가 Pro의 가치를 보여주는 게 아니라, 오히려 빈 화면을 보여준다. [C][A]**

`ProTemplateInfoSheet`는 `DashboardPreviewCard(snapshot: previewSnapshot)`를 보여준다
(`LockTodoNote/Features/Templates/TemplatePickerView.swift:150`, `:224`).
`previewSnapshot`은 현재 스냅샷의 `lockScreenLayout`만 Pro 템플릿으로 바꿀 뿐,
**그 템플릿이 필요로 하는 데이터를 채우지 않는다.**

- 이미지 템플릿: `PreviewImage`가 `snapshot.imageFileName`을 읽는데
  (`LockTodoNote/Features/Home/DashboardPreviewCard.swift`, `PreviewImage`),
  사진을 한 번도 넣은 적 없는 무료 사용자에게는 `nil`이다.
  결과적으로 **"사진 템플릿"의 미리보기에 회색 `photo` 심볼 placeholder가 뜬다.**
  즉 팔려는 물건 자리가 빈 상자로 보인다.
- D-Day 템플릿: `ddayTitle`/`ddayTargetDate`가 비어 있으면 `PreviewDday`는 literal `"D-Day"` 문자열만 렌더한다.
  오른쪽 pane은 `.ddayMemo`라서 메모만 보여주는데, Todo만 쓰는 사용자에게는 "메모 없음"이 뜬다.
  **D-Day 카드 미리보기가 "D-Day" + "메모 없음"으로 끝난다.**
- Memo + Todo 템플릿: Todo만 있는 사용자에게 왼쪽 절반이 "메모 없음"이다.

입력 필드(`needsTemporaryPreviewInput`, `TemplatePickerView.swift:258`)는
**Todo와 Memo가 둘 다 비어 있을 때만** 나타난다. 즉 실제 데이터가 있는 사용자는
미리보기를 **조작할 수 없고**, 데이터가 없는 사용자만 조작할 수 있다. 정확히 반대다.
GA4에서 `pro_preview_interacted`가 36 events / **1 user**인 것이 이 구조를 그대로 증명한다. [A]

**2. Paywall이 "왜 돈을 내야 하는가"가 아니라 "얼마인가"만 말한다. 그리고 약속 중 하나는 거짓이다. [C]**

`PaywallView.benefits`(`LockTodoNote/Features/Paywall/PaywallView.swift:91`)는 6개 항목을 나열하는데,
그중 **"Morning Briefing options" (`paywall.benefit.briefing`)는 코드에 게이팅이 전혀 없다.**
Morning Briefing은 `SettingsTabView.remindersSection`의 아침/저녁 로컬 알림 토글이 전부이고
(`LockTodoNote/Features/Settings/SettingsTabView.swift:78-90`, `remindersSection`),
`purchases.canUse(...)` 호출이 한 군데도 없다. **무료 사용자가 이미 100% 쓰고 있는 기능을 Pro 혜택으로 팔고 있다.**

또한 Paywall 상단에 **결과 미리보기가 없다.** 텍스트 6줄 → 상품 카드 → "계속하기" 버튼이 전부다.
사용자가 방금 탭한 Pro 템플릿이 무엇이었는지조차 Paywall 화면에 나타나지 않는다.
(`requestPaywall(source:pendingTemplate:)`은 `pendingProTemplate`를 저장하지만
`AppEnvironment.swift:252`, 이 값은 **구매 성공 후 적용**에만 쓰이고 Paywall UI에 전달되지 않는다.)

**3. 7일 무료 체험이 있는데 버튼이 그 사실을 말하지 않는다. 이것이 높은 취소율의 유력한 원인이다. [C][A][D]**

`docs/competitor-analysis-live-note-live-memo.md`에 "연간 상품의 7일 무료 체험이 App Store Connect에 구성되어 있다"고 기록되어 있다. [D]
코드도 이를 읽을 준비가 되어 있다 — `PurchaseService.freeTrial(for:)`, `PaywallView.trialText(for:)` (`PaywallView.swift:338`).
그런데 `trialText`는 **상품 카드 안의 작은 초록 caption**으로만 표시되고,
하단 고정 CTA 버튼은 항상 `paywall.continue` = **"계속하기"** 다 (`PaywallView.swift:233-242`).

사용자 관점: "계속하기"는 결제 버튼으로 읽히지 않는다. 다음 화면을 보러 가는 버튼으로 읽힌다.
탭하면 StoreKit 결제 시트가 갑자기 뜬다. → 취소.
GA4의 `purchase_started` 13 / `purchase_cancelled` 9 (**취소율 69%**)는 이 가설과 정확히 일치한다. [A]

**4. 고의도(high-intent) Paywall 트리거 두 개가 코드상 죽어 있다. [C]**

- `offerPaywallForShortcutLimit()` (`LockTodoNote/App/AppEnvironment.swift:158`) — **호출하는 곳이 전혀 없다.**
  Shortcut 하루 5회 한도에 걸리면 App Intent가 "Pro로 업그레이드하세요" 문자열만 반환하고
  (`Extensions/WidgetExtension/GlanceCardAppIntents.swift:34-35`), 앱을 열어도 Paywall은 뜨지 않는다.
- `offerPaywallAfterFirstLockScreenSuccess()` (`AppEnvironment.swift:128`) — 호출처는 딱 하나,
  Today 탭의 수동 "시작" 버튼이다 (`LockScreenTabView.swift:518`).
  그런데 온보딩의 `activate()`와 `bootstrap()`의 `ensureLiveActivityStarted()`(`AppEnvironment.swift:170`)가
  **Live Activity를 조용히 자동 시작**해 버리고, 그러면 Today 카드의 시작 버튼은
  `.disabled(... || state.isRunning)`으로 비활성화된다.
  **정상 경로를 밟은 사용자에게 이 트리거는 사실상 도달 불가능하다.** [I]

즉 실제로 살아 있는 트리거는 `lock_screen_template`(Pro 템플릿 탭), `settings_pro_card`, `theme_color`,
`day_2_soft_hint`, `trial_expired` 다섯 개이고, GA4상 대부분은 템플릿 탭에서 온다. [A][I]

**5. Pro가 "잠금화면 레이아웃 4종"으로만 보인다. 번들의 절반은 미구현이거나 무료다. [C]**

`ProFeature`는 8개 case를 선언한다 (`Packages/.../Models/CardEnums.swift:130`).
그중 실제로 게이팅에 쓰이는 건 5개뿐이다:

- `memoTodoTemplate`, `imageMemoTemplate`, `imageTodoTemplate`, `ddayMemoTemplate` → 템플릿 4종
- `themes` → accent 색상 (`SettingsTabView.swift:569`)
- `unlimitedShortcuts` → `canUse`로는 한 번도 호출되지 않고, Intent가 raw `isPro`를 직접 읽는다
- **`cardCustomization` — `canUse` 호출 0건. 텍스트 굵기/크기/프라이버시 모드 전부 무료.**
- **`displayStyle` — `canUse` 호출 0건.**

그리고 iCloud Sync는 **코드에 전혀 존재하지 않는다** (CloudKit/NSUbiquitous grep 0건).
Advanced Dynamic Island도 별도 게이트가 없다 — Dynamic Island는 통째로 무료다.

결과: 사용자 눈에 Pro는 **"템플릿 몇 개 + 색상"** 이다. 반복 사용 가치가 아니라 일회성 꾸미기다. [I]

---

## 2. Current Purchase Architecture

### 2.1 상품 및 Entitlement

| 항목 | 위치 |
|---|---|
| Product ID 정의 | `Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Models/ProductIdentifiers.swift:10-13` |
| Monthly | `com.namslab.glancecard.monthly` |
| Yearly (레거시, 오타 그대로 운영 중) | `com.namslab.glancecard.yealy` |
| Yearly (교정본, 병행 조회) | `com.namslab.glancecard.yearly` |
| Lifetime | `com.namslab.glancecard.lifetime` |
| 우선순위 (lifetime > yearly > monthly) | `ProductIdentifiers.priority(_:)` `:26` |
| Entitlement 모델 | `ProductIdentifiers.swift:48` |
| 기능 판정 | `Entitlement.canUse(_:)` `:88` |
| 오프라인 캐시 | `Entitlement(cachedJSON:)` `:97`, `cachedJSON` `:118` |

### 2.2 PurchaseService (`LockTodoNote/Core/Purchases/PurchaseService.swift`)

| 흐름 | 위치 | 비고 |
|---|---|---|
| 앱 실행 시 entitlement 새로고침 | `refreshEntitlement()` `:49` | `Transaction.currentEntitlements`가 source of truth |
| 백그라운드 트랜잭션 리스너 | `init` 내 `Transaction.updates` `:36` | finish + refresh |
| 상품 조회 | `loadProducts()` `:88` | `ProductIdentifiers.allSet` 일괄 조회, 실패 시 `productLoadFailed` |
| 구매 | `purchase(_:)` `:152` | `.success/.cancelled/.pending/.failed` 4분기 |
| 복원 | `restore()` `:198` | `AppStore.sync()` 후 재조회, `.restored/.noPurchases/.failed` |
| 구독 만료 | `refreshEntitlement()` 내 `expirationDate > Date()` 필터 `:57` | |
| Lifetime | `expirationDate == nil` → `?? true`로 통과 `:57` | |
| 연간 절약률 계산 | `yearlySavingsPercent` `:120` | **계산만 하고 UI에서 사용처 0건** |
| StoreKit 무료 체험 조회 | `freeTrial(for:)` `:139` | `isEligibleForIntroOffer` 미확인 |
| 24시간 임시 체험 | `canStartTemporaryTrial` `:209`, `startTemporaryTrial()` `:215`, `grantWidgetInstallTrial()` `:222` | |

### 2.3 Paywall 진입 경로 (전수)

| source 값 | 호출 위치 | 살아 있는가 |
|---|---|---|
| `lock_screen_template` | `TemplatePickerView.swift:41`, `LockScreenTabView.swift:57` | **주 경로** |
| `settings_pro_card` | `SettingsTabView.swift:159` | 살아 있음 |
| `theme_color` | `SettingsTabView.swift:571` (`ColorThemePicker.select`) | 살아 있음 |
| `day_2_soft_hint` | `AppEnvironment.swift:154` ← `bootstrap()` `:122` | 살아 있음, activation 완료 필요 |
| `trial_expired` | `AppEnvironment.swift:145` ← `bootstrap()` `:121` | 살아 있음 (24h 체험 사용자 한정) |
| `first_lock_screen_success` | `AppEnvironment.swift:138` ← `LockScreenTabView.swift:518` | **사실상 도달 불가** (2.4 참조) |
| `shortcut_limit_reached` | `AppEnvironment.swift:160` | **호출처 없음 — 완전 사망** |

Paywall 표시 자체는 `RootView.swift:37`의 `.sheet(item: $environment.paywallRequest)` 한 곳이다.
`requestPaywall`(`AppEnvironment.swift:252`)이 **시트 표시 시점이 아니라 요청 시점에** `paywall_seen`을 로깅한다.

### 2.4 `first_lock_screen_success`가 죽은 이유 [C][I]

```text
온보딩 activate()            → dashboard.startLiveActivity() 직접 호출 (paywall 트리거 없음)
completeOnboarding()        → ensureLiveActivityStarted()   (paywall 트리거 없음)
bootstrap() 매 실행          → ensureLiveActivityStarted()   (paywall 트리거 없음)
Today 탭 "시작" 버튼          → startLiveActivity() → offerPaywallAfterFirstLockScreenSuccess()
                              ↑ 단 state.isRunning이면 버튼이 .disabled
```

자동 시작이 항상 먼저 성공하므로 수동 버튼을 누를 기회가 거의 없다.

### 2.5 Pro 템플릿 탭 흐름

```text
TemplatePickerView.select(_:)  (:56)  또는  LockScreenTabView.selectTemplate(_:)  (:209)
  └─ isLocked? ── yes ──▶ analytics.proTemplateTapped(template)
                          analytics.proInfoSheetViewed(template)     ← 같은 줄에서 즉시
                          infoTemplate = template
                            └─ ProTemplateInfoSheet.onAppear
                                 └─ analytics.proPreviewViewed(template)  ← 같은 순간
                            └─ 사용자가 CTA 탭
                                 └─ environment.requestPaywall(source:"lock_screen_template",
                                                               pendingTemplate: template)
                                      └─ analytics.paywallSeen("lock_screen_template")
                                      └─ PaywallView 표시
```

### 2.6 구매 완료 후

`PaywallView.purchase()` `:283` → `.success` → `purchaseCompleted` 로깅 →
`environment.applyPendingProTemplate()` (`AppEnvironment.swift:258`) → `dismiss()`.

`applyPendingProTemplate()`는 템플릿을 적용하고 `dashboard.publish()`를 호출한다.
**Live Activity 재시작도, 성공 확인 화면도, 축하 애니메이션도 없다.**
사용자는 Paywall이 닫히고 원래 화면으로 돌아올 뿐이다.

---

## 3. Free User Journey

무료 사용자가 실제로 겪는 흐름을 코드 순서대로 재구성한 것이다.

### 단계 1 — 설치 / 첫 실행

`LockTodoNoteApp` → `AppEnvironment.init` (마이그레이션 동기 수행) → `RootView`.
`needsOnboarding`이 true면 `fullScreenCover`로 온보딩.

### 단계 2 — 온보딩 (4단계, `OnboardingView.swift`)

| step | 화면 | 사용자가 할 수 있는 것 |
|---|---|---|
| `intro` | 잠금화면 미리보기(빈 상태) + "Your day, on your Lock Screen" | 시작 / 건너뛰기 |
| `firstTodo` | Todo 1개 입력 (자동 포커스) | 입력 → 다음 |
| `activate` | 미리보기 + "Show on Lock Screen" | Live Activity 실제 시작 / "나중에" |
| `automation` | Shortcuts 자동화 3개 안내 | Shortcuts 열기 / 완료 |

**Pro는 온보딩 전 구간에서 단 한 번도 언급되지 않는다.** [C]
GA4: `onboarding_start` 67명 → `onboarding_complete` 59명 → `activation_complete` 58명.
활성화 퍼널 자체는 매우 건강하다 (first_open 71명 대비 82% 활성화). [A]

### 단계 3 — 첫 Todo / Memo

Today 탭 하단 Quick Capture가 인라인으로 항상 노출된다 (`LockScreenTabView.quickCapture` `:214`).
Todo/Memo 세그먼트 전환, 여러 줄 붙여넣기 자동 분리(`saveCapture()` `:466`) 모두 무료.
개수 제한 없음. [C]

### 단계 4 — Live Activity

무료로 제한 없이 사용. 12시간 stale (`LiveActivityService.activityDuration`).
`ensureLiveActivityStarted()`가 앱 실행마다 자동 복구. Dynamic Island도 자동 동반. 전부 무료. [C]

### 단계 5 — 오늘 화면 사용

Todo 완료 토글, 삭제, 메모 편집, 완료 항목 접기, Shortcut 기본 저장 위치 선택 — 전부 무료.
잠금화면에서 직접 Todo 완료(`ToggleTodoIntent`)도 무료.

### 단계 6 — Calendar

`CalendarTabView.swift`에 `canUse` / `paywall` / `Pro` 문자열이 **0건**. 전부 무료. [C]

### 단계 7 — Display (Live / Widget / Island)

`DisplayContinuityView.swift`에도 게이팅 0건. 위젯 설치 확인 버튼을 누르면
오히려 **24시간 Pro 체험이 공짜로 주어진다** (`grantWidgetInstallRewardIfNeeded()` `:198`). [C]

### 단계 8 — Pro 템플릿 발견

Today 탭 상단의 5칸 compact 템플릿 버튼(`compactTemplateButton` `:158`) 또는
템플릿 목록 화면에서 발견. 잠긴 것은 자물쇠 아이콘 + "Pro" 배지.
`userFacingCases` 5개 중 **3개가 Pro**: `memoTodo`, `imageTodo`, `ddayMemo`. 무료는 `calendarItems`, `dateTodo`.

GA4: `lock_screen_template_changed` 201 events / 38명, `pro_template_tapped` 116 events / 38명.
**사용자당 Pro 템플릿을 평균 3.05번 탭한다.** 잠금 사실을 알고도 반복해서 누른다. [A]

### 단계 9 — Pro Preview (`ProTemplateInfoSheet`)

앞서 1번에서 설명한 대로, 대부분의 사용자에게 **비어 보이는** 미리보기가 뜬다.
설명 1줄, CTA "이미지 카드 사용 / LockTodoNote Pro에 포함됨", "나중에".

### 단계 10 — Paywall

제목 → 부제 → 혜택 6줄 → 상품 3개 → (24시간 무료 체험 링크) → 약관 → 하단 "계속하기".

### 단계 11 — plan 선택

`selectDefaultProduct()` `:278`이 연간을 기본 선택. 정렬은 연간 → 월간 → 평생 (`productRank` `:273`).
연간에만 "Best Value" 배지와 "월 ₩X" 환산가.
**plan 선택 이벤트가 로깅되지 않는다.** (`ProductCard`의 `onTap`은 `selectedProductId` 대입만 한다, `:163`)

### 단계 12 — purchase

"계속하기" → `purchase_started` 로깅 → StoreKit 시트 → 취소 또는 완료.

---

## 4. 핵심 질문 12개에 대한 답

### Q1. 무료만으로 핵심 가치를 거의 다 쓸 수 있는가?

**그렇다. 거의 전부다.** [C]

잠금화면에서 오늘 할 일을 보고, 잠금화면에서 직접 완료하고, Dynamic Island로 확인하고,
위젯으로 이어 보고, 캘린더로 날짜를 옮기고, Shortcut으로 하루 5번 추가하고,
프라이버시 모드 4종을 고르고, 글자 크기/굵기를 조절하고, 아침·저녁 알림을 켜는 것 —
**전부 무료다.** 이 앱의 App Store 한 줄 설명을 무료 버전이 100% 충족한다.

### Q2. "Pro를 사야 하는 이유"를 5초 안에 이해할 수 있는가?

**아니다.** Paywall 제목 "잠금화면을 더 나답게"는 결과가 아니라 분위기다.
부제 "사진, 디데이, 무제한 단축어로 잠금화면을 나만의 것으로"는 기능 나열이다.
5초 안에 눈에 들어오는 구체적 정보는 **가격 세 줄**뿐이다. [C][I]

### Q3. Pro가 "템플릿 몇 개 더"처럼 보이지 않는가?

**정확히 그렇게 보인다.** 실제 게이팅되는 것이 템플릿 4종 + accent 색상 + Shortcut 한도뿐이고,
Paywall 혜택 6줄 중 3줄이 템플릿 이름이다. [C]

### Q4. 무료 사용자에게 결과를 너무 많이 보여줘서 결제 이유가 사라지는가?

**핵심 결과는 그렇다. 그러나 Pro 결과는 정반대로 너무 안 보여준다.**
무료 결과(잠금화면에 오늘이 뜬다)는 완전히 제공되고, Pro 결과(사진이 들어간 잠금화면)는
미리보기에서조차 빈 placeholder로 보인다. 두 실수가 동시에 있다. [C][I]

### Q5. 반대로 Pro를 전혀 체험할 수 없어서 가치가 전달되지 않는가?

**체험 수단은 오히려 과잉이다. 전달이 안 될 뿐이다.**
24시간 임시 체험이 두 갈래로 존재한다 — Paywall 하단 링크(`PaywallView.swift:186`)와
위젯 설치 보상(`grantWidgetInstallTrial()`). 그런데 GA4상 `temporary_pro_trial_started`는 **3명**뿐이다. [A]
Paywall 하단, 상품 카드 아래, 본문 텍스트 크기의 평범한 링크라서 보이지 않는다. [C][I]

### Q6. 결제 전에 실제 사용자 Todo/Memo를 Pro Preview에 넣어 보여주는가?

**부분적으로만. 그리고 가장 중요한 부분이 빠져 있다.** [C]
`previewSnapshot`(`TemplatePickerView.swift:224`)은 사용자의 실제 Todo/Memo를 그대로 쓴다 — 여기까지는 좋다.
그러나 **사진 슬롯과 D-Day 슬롯은 비어 있고, 채울 방법을 주지 않는다.**
결과적으로 사진 템플릿은 사진 없이, D-Day 템플릿은 날짜 없이 미리보기된다.

### Q7. Pro 기능 탭 시 "왜 좋은지"보다 가격이 먼저 나오는가?

**아니다. 이 부분은 설계가 옳다.** 탭 → info sheet(설명 + 미리보기) → CTA → Paywall 순서다.
문제는 순서가 아니라 그 info sheet가 설득을 못 한다는 것이다. [C]

### Q8. 월/연/평생이 결정을 망설이게 하는가?

**그렇다.** 세 상품이 동시에 라디오 버튼으로 나열되고(`productList` `:142`),
연간에만 비교 정보(월 환산가)가 있고 평생에는 아무 맥락이 없다.
사용자는 "₩17,000 한 번"과 "₩7,700/년"을 스스로 계산해서 비교해야 한다.
계산해 보면 2.2년이면 본전이므로 **평생이 합리적 선택으로 보인다.** [C][I]

### Q9. Lifetime이 Yearly를 잠식하는가?

**그렇다. 구조적으로.** [D][I]
₩17,000 ÷ ₩7,700 = **2.21년 회수**. 잠금화면 앱을 2년 이상 쓸 의향이 조금이라도 있으면 평생이 정답이다.
그리고 평생 구매자는 LTV가 ₩17,000에서 영원히 멈춘다.
통상 권장 비율은 연간의 3~5배다. 지금은 2.2배로 **너무 싸다.**

### Q10. 월간이 너무 싸거나 Lifetime이 너무 싸서 구독 이유가 약한가?

**월간(₩1,100)은 문제가 아니다** — 연간이 42% 절약이라 연간 유도는 수학적으로 성립한다.
**Lifetime(₩17,000)이 문제다.** 연간 구독의 상단을 잘라 버린다. [D][I]

### Q11. 연간이 메인 선택지로 충분히 강조되는가?

**절반만.** 기본 선택 ✓, 맨 위 배치 ✓, "Best Value" 배지 ✓, 월 환산가 ✓.
그러나 **42% 절약이라는 가장 강한 숫자가 화면에 없다.**
`yearlySavingsPercent`(`PurchaseService.swift:120`)와 `paywall.savePercent` 문자열("%d%% 절약")이
**둘 다 존재하는데 렌더링하는 코드가 없다.** 계산해 놓고 안 쓴다. [C]

### Q12. 무료 체험이 필요한 상품 구조인가?

**이미 있다. 문제는 없어서가 아니라 안 보여서다.** [C][D]
연간 상품에 7일 무료 체험이 구성되어 있고, 앱에는 별도의 24시간 템플릿 체험도 있다.
그런데 CTA 버튼은 "계속하기"이고, 두 체험의 차이를 설명하는 문구가 어디에도 없다.
**새 trial을 만들 필요는 없다. 있는 trial을 버튼에 올리면 된다.**

---

## 5. Feature Gating 전수 표

`✅ 무료` = 게이팅 코드 없음 / `🔒 Pro` = `canUse` 또는 `isPro` 체크 존재 / `❌ 미구현`

| 기능 | 무료 | Pro | 제한 방식 (코드 위치) | 현재 가치 | 결제 기여 가능성 |
|---|---|---|---|---|---|
| 기본 Todo (무제한) | ✅ | — | 게이팅 없음 (`CardStore`) | 매우 높음 | 낮음 (건드리면 안 됨) |
| 기본 Memo (무제한) | ✅ | — | 게이팅 없음 | 높음 | 낮음 (건드리면 안 됨) |
| Calendar | ✅ | — | `CalendarTabView.swift` 게이팅 0건 | 높음 | 낮음 |
| Live Activity | ✅ | — | `LiveActivityService.start`는 `isPro`를 페이로드에만 씀 | 매우 높음 | 낮음 (핵심 activation) |
| 잠금화면 Todo 완료 | ✅ | — | `ToggleTodoIntent` 게이팅 없음 | 매우 높음 | 낮음 |
| Dynamic Island (전체) | ✅ | — | `GlanceCardLiveActivity.swift` 게이팅 0건 | 높음 | 낮음 |
| Widget (accessoryRectangular/Inline) | ✅ | — | `isPremium`은 analytics 파라미터로만 사용 (`GlanceCardLockScreenWidget.swift:432`) | 중간 | 낮음 |
| Shortcuts (하루 5회) | ✅ | 🔒 무제한 | `GlanceCardAppIntents.swift:34`, `AppGroupKeys.freeShortcutDailyLimit = 5` | 중간 | **중간 (트리거 사망 중)** |
| 템플릿 `calendarItems` | ✅ | — | `proFeature == nil` (`CardEnums.swift:108`) | 높음 (기본값) | — |
| 템플릿 `dateTodo` / `dateMemo` | ✅ | — | `proFeature == nil` | 중간 | — |
| 템플릿 `memoTodo` | — | 🔒 | `ProFeature.memoTodoTemplate` | 중간 | 중간 |
| 템플릿 `imageTodo` / `imageMemo` | — | 🔒 | `ProFeature.imageMemoTemplate` / `.imageTodoTemplate` | **높음 (최강 후보)** | **높음** |
| 템플릿 `ddayMemo` | — | 🔒 | `ProFeature.ddayMemoTemplate` | 중간~높음 | 중간 |
| 이미지 업로드 자체 | ✅ | — | `LockScreenImageStore` 게이팅 없음, `PhotosPicker`는 템플릿 잠금으로 간접 차단 | — | — |
| D-Day 데이터 편집 | ✅ | — | `DdayEditorSheet` 게이팅 **0건** — 저장은 되지만 볼 수가 없음 | 낮음 | 낮음 |
| 테마 (Light/Dark/System) | ✅ | — | `themeStore.mode` 게이팅 없음 | 중간 | 낮음 |
| Accent 색상 9종 | — | 🔒 | `ProFeature.themes` (`SettingsTabView.swift:569`) | 낮음~중간 | 낮음 |
| 글자 크기 (0.85~1.25) | ✅ | — | `textStyleSection` 게이팅 없음 | 중간 | — |
| 글자 굵기 (regular/bold) | ✅ | — | 게이팅 없음 | 낮음 | — |
| 정렬 / 콘텐츠 섹션 선택 | ✅ | — | 게이팅 없음 | 중간 | — |
| 배경 / 이미지 효과 | ❌ | ❌ | **미구현** — 배경은 `Color.black.opacity(0.8)` 하드코딩 | — | — |
| Privacy 모드 4종 | ✅ | — | 게이팅 없음 | 높음 | 낮음 |
| Morning Briefing | ✅ | — | **게이팅 0건인데 Paywall이 Pro 혜택으로 광고함** (`PaywallView.swift:128`) | 낮음 | **음수 (신뢰 훼손)** |
| iCloud Sync | ❌ | ❌ | **미구현** — CloudKit 참조 0건 | — | — |
| Advanced Dynamic Island | ❌ | ❌ | **미구현** — 별도 게이트 없음 | — | — |
| 공유 확장 링크 저장 | ✅ | — | `ShareViewController` 게이팅 없음 | 낮음 | 낮음 |
| `ProFeature.cardCustomization` | — | — | **선언만 존재, `canUse` 호출 0건 — 죽은 케이스** | — | — |
| `ProFeature.displayStyle` | — | — | **선언만 존재, `canUse` 호출 0건 — 죽은 케이스** | — | — |
| 24시간 임시 Pro 체험 | ✅ | — | 템플릿 4종만 해제 (`CardEnums.swift:143`) | 중간 | 중간 |

---

## 6. 무료 기능이 너무 강한가?

**결론: 무료는 "너무 강하다"기보다 "완결되어 있다".**

사용자가 이 앱을 설치한 이유 = "앱 안 열고 잠금화면에서 오늘 할 일 보기".
그 목적은 무료로 **100% 달성된다.** 그것도 매우 잘 달성된다:

- 잠금화면 표시 ✅
- 잠금화면에서 완료 ✅
- Dynamic Island ✅
- 위젯 fallback ✅
- 날짜 이동 ✅
- Memo/Todo 전환 ✅
- 프라이버시 4모드 ✅
- 글자 크기 조절 ✅
- 하루 5회 Shortcut ✅ (대부분 사용자에게 충분)

### 왜 굳이 Pro를 결제하지 않아도 되는가

> "내 할 일이 잠금화면에 보인다. 잠금화면에서 체크된다. 글자도 키웠다. 색깔만 파란색 대신
> 초록색으로 못 바꾸고, 사진 배경을 못 넣는다. 근데 사진 배경은 어차피 잠금화면 배경화면이
> 따로 있으니 굳이 필요 없다."

이것이 무료 사용자의 정직한 내적 독백이다. [I]

### 핵심 무료 경험은 유지하면서 Pro 가치를 어디서 만들 것인가

**절대 막지 말 것**: 첫 Todo, 기본 Memo, 기본 Live Activity, 기본 Widget, Calendar, 잠금화면 완료.
GA4상 activation 82%는 이 앱의 가장 큰 자산이다. 여기 손대면 다운로드가 그대로 이탈로 바뀐다. [A][I]

**Pro 가치를 만들 자리 — 우선순위 순:**

1. **시각적 개인화의 결과물** — 사진 템플릿은 이미 있다. 문제는 가치 전달이지 기능이 아니다.
   "내 아이 사진 + 오늘 할 일"이 잠금화면에 뜨는 **완성된 결과 이미지**를 결제 전에 보여줘야 한다.
2. **반복 자동화** — Shortcut 무제한은 이미 있으나 트리거가 죽어 있다. 살리면 즉시 고의도 접점이 된다.
3. **다중 컨텍스트** — 현재 D-Day는 **슬롯 1개**다 (`LockScreenSettings.ddayTitle` 단일 필드).
   여러 D-Day, 여러 저장된 템플릿 프리셋은 반복 가치가 있고 무료 activation을 해치지 않는다. (신규 개발 필요)
4. **미구현 번들의 실현** — iCloud Sync, 고급 Dynamic Island는 지금 팔 수 없다. 만들거나 광고를 내려야 한다.

---

## 7. Pro 가치 개별 평가

| Pro 기능 | 돈 낼 만한가 | 첫눈에 가치가 보이나 | 반복 사용 | 일회성 | 단독 결제 유도 | 번들 필요 |
|---|---|---|---|---|---|---|
| 이미지 템플릿 | **예 — 최강** | **현재 아니오** (빈 placeholder) | 예 (매일 봄) | 아니오 | **가능** | 불필요 |
| D-Day 템플릿 | 예 | 현재 아니오 (빈 "D-Day") | 예 (매일 카운트다운) | 아니오 | 가능 (이벤트 있는 사용자) | 권장 |
| Memo + Todo 레이아웃 | 보통 | 보통 | 예 | 아니오 | 어려움 | 필요 |
| Accent 색상 9종 | **아니오** | 예 (즉시 보임) | 아니오 | **예** | 불가능 | 필요 |
| 무제한 Shortcuts | 예 (Power User 한정) | 아니오 (한도를 만나야 앎) | 예 | 아니오 | **가능 — 단 트리거 사망** | 불필요 |
| Morning Briefing | **판매 불가** | — | — | — | **불가 — 무료 기능임** | 즉시 제거 대상 |
| iCloud Sync | 예 (있다면) | 예 | 예 | 아니오 | 가능 | — (**미구현**) |
| Advanced Dynamic Island | 불명 | 아니오 | 예 | 아니오 | 불가능 | — (**미구현**) |

**핵심 판단:** 지금 팔 수 있는 것은 사실상 **이미지 템플릿 하나**다.
나머지는 보조거나(D-Day, Memo+Todo), 단독으로는 못 팔거나(색상), 존재하지 않는다(Sync, 고급 Island).
따라서 Paywall은 6개를 균등 나열할 게 아니라 **이미지 결과 1개를 크게 보여주고 나머지를 딸려 보내야 한다.** [I]

---

## 8. Paywall UI / 카피 분석 (`LockTodoNote/Features/Paywall/PaywallView.swift`)

| 요소 | 현재 구현 | 위치 | 평가 |
|---|---|---|---|
| 제목 | "잠금화면을 더 나답게" | `:76` | 결과 없음, 감성만 |
| 부제 | "사진, 디데이, 무제한 단축어로 잠금화면을 나만의 것으로." | `:79` | 기능 나열 |
| 결과 미리보기 | **없음** | — | **가장 큰 결손** |
| 혜택 리스트 | 6줄 (사진/D-Day/Memo+Todo/단축어/색상/Morning Briefing) | `:91-133` | 1줄은 사실과 다름 |
| 가격 표시 | `product.displayPrice` | `:388` | 정확 |
| 기본 선택 | 연간 (`yearlyProduct?.id ?? products.first`) | `:278` | **옳음** |
| 상품 순서 | 연간 → 월간 → 평생 (`productRank`) | `:273` | **옳음** |
| Best Value | 연간에만 배지 | `:333` | 있음 |
| **할인율 강조** | **없음** — `yearlySavingsPercent` 미사용 | `PurchaseService.swift:120` | **누락** |
| 월 환산가 | 연간에만 표시 | `:402` | 좋음 |
| Lifetime 맥락 | **없음** — 가격만 | `:388` | 비교 불가 |
| Trial 표기 | 상품 카드 내 작은 초록 caption | `:338`, `:369` | **CTA에 없음** |
| 버튼 문구 | 항상 "계속하기" | `:239` | **취소율의 유력 원인** |
| 24시간 체험 | 상품 카드 **아래**, plain 텍스트 버튼 | `:186` | 발견 불가 |
| Restore | 우상단 toolbar 버튼 | `:47` | 있음 |
| Terms / Privacy | footer 링크 | `:207-216` | 있음 |
| 닫기 | 좌상단 X, 지연 없음 | `:41` | **정직함 — 유지할 것** |
| Loading | `ProgressView` | `:143` | 있음 |
| Error state | "가격을 불러오지 못했어요" + 재시도 | `:146-172` | 있음 |
| 광고 없음 문구 | footer에 있음 | `:200` | 신뢰 요소, **위로 올릴 가치 있음** |

### 이 화면을 처음 보는 사람이 얻는 답

```text
"왜 돈을 내야 하지?"  →  답을 못 얻는다. 6개 명사가 나열될 뿐이다.
"얼마인가?"           →  즉시, 명확하게 얻는다. 세 줄로.
```

Paywall은 **가격 화면이지 가치 화면이 아니다.** [C][I]

한 가지는 명확히 칭찬해야 한다: **다크 패턴이 없다.**
닫기 버튼 즉시 노출, 전 가격 전체 표시, 자동 갱신 고지, 광고 없음 약속.
개선 과정에서 이 정직함은 그대로 유지되어야 한다.

---

## 9. Pro Preview 집중 분석

대상: `ProTemplateInfoSheet` (`LockTodoNote/Features/Templates/TemplatePickerView.swift:128-281`)

| 점검 항목 | 현재 | 근거 |
|---|---|---|
| 실제 사용자 Todo/Memo 사용 | **예** | `previewSnapshot`이 `dashboard.currentSnapshot()` 기반 `:225` |
| 가짜 샘플 데이터 | 아니오 | `DashboardPreviewCard` 주석: "It never uses sample content" |
| 사용자가 옵션을 바꿔볼 수 있나 | **Todo와 Memo가 둘 다 없을 때만** | `needsTemporaryPreviewInput` `:258` |
| 사진을 미리 넣어볼 수 있나 | **아니오** | `previewSnapshot`이 `imageFileName`을 설정하지 않음 |
| D-Day 날짜를 미리 넣어볼 수 있나 | **데이터 있는 사용자는 아니오** | 같은 `needsTemporaryPreviewInput` 조건 |
| 실제 잠금화면과 동일한가 | 레이아웃은 동일, **콘텐츠는 비어 있음** | `PreviewImage` fallback = `photo` 심볼 |
| Preview 후 CTA가 자연스러운가 | 예 ("이미지 카드 사용") | `proCTA` `:296` |
| Preview → Paywall이 긴가 | 아니오, 1탭 | `:41` |
| 결제 욕구를 높이는가 | **아니오 — 낮춘다** | 빈 미리보기는 "이거 별거 없네"를 만든다 [I] |
| 무료로 결과를 너무 주는가 | 아니오 | 오히려 너무 안 준다 |

### 원칙 대조

```text
원칙: 결제 전에 모든 결과를 무료로 다 주지 않는다.
      하지만 사용자가 Pro의 가치를 충분히 이해하게 한다.

현재: 결과를 주지도 않고 (사진 없음, D-Day 없음)
      이해도 못 시킨다 (빈 placeholder)
      → 두 조건 모두 실패
```

**가장 중요한 단일 발견이다.** GA4에서 `pro_preview_viewed` 38명 → `paywall_seen` 36명으로
탈락은 적어 보이지만, 이는 사용자가 **설득되어서** 넘어간 게 아니라
info sheet에 정보가 없어서 그냥 넘어간 것일 가능성이 높다. 실제 탈락은 Paywall 다음 단계에 몰려 있다
(36명 → `purchase_started` 10명, **72% 이탈**). [A][I]

---

## 10. Pricing Analysis

### 실제 가격 (국내 App Store, `docs/competitor-analysis-live-note-live-memo.md` 확인)

| 상품 | 가격 | 연간 대비 | 비고 |
|---|---:|---:|---|
| Monthly | ₩1,100 | — | 연 환산 ₩13,200 |
| Yearly | ₩7,700 | 기준 | 월 환산 ₩642 |
| Lifetime | ₩17,000 | **2.21배** | 회수 2.21년 |

연간 절약률: **42%** (₩13,200 → ₩7,700). 코드도 이 값을 계산한다 (`yearlySavingsPercent`).

### 경쟁 대비 [D]

| 앱 | Monthly | Yearly | Lifetime | Lifetime/Yearly |
|---|---:|---:|---:|---:|
| **LockTodoNote** | ₩1,100 | ₩7,700 | ₩17,000 | **2.21x** |
| Live Memo | ₩1,500 | ₩9,900 | ₩24,000 | 2.42x |
| Live Note | ₩2,900 | ₩17,900 | ₩49,000 | 2.74x |

**LockTodoNote는 세 가격 전부 최저가다.** 가격이 결제 장애물일 가능성은 매우 낮다. [D][I]

### 평가

| 질문 | 답 |
|---|---|
| Yearly 대비 Lifetime 비율 | 2.21배 — **업계 권장 3~5배 대비 지나치게 낮음** |
| Lifetime이 Yearly를 죽이는가 | **예.** 2.2년만 쓰면 본전이고, 잠금화면 앱은 2년 이상 쓸 가능성이 높다 |
| Monthly가 연간 전환을 막는가 | 아니오. 42% 차이는 충분히 크다 |
| 세 상품 동시 노출이 피로를 주는가 | **예.** 특히 Lifetime에 비교 맥락이 없어 계산을 사용자에게 떠넘긴다 |
| 기본 선택 상품 | 연간 — 올바름 |
| Annual Best Value가 실제로 강조되는가 | **절반만.** 배지는 있고 42% 숫자가 없다 |
| Lifetime을 내려야 하는가 | **예 — 노출을 낮추거나 인상.** 단 신규 cohort에서만 실험 |
| 가격 인상이 필요한가 | Lifetime만. 구독가는 지금 건드릴 이유 없음 |
| Trial이 필요한가 | **이미 있다. 노출이 필요하다** |

**가격을 낮추는 것은 해법이 아니다. 이미 최저가이고, 낮추면 LTV만 깎인다.** [D][I]

---

## 11. purchase_cancelled 원인 분석

GA4: `purchase_started` 13 events / 10명, `purchase_cancelled` 9 events / 7명 → **취소율 69%**.
정상 StoreKit 취소율(40~60%)보다 확연히 높다. [A]

| 가설 | 근거 | 확신도 |
|---|---|---|
| **A. "계속하기" 버튼이 결제 버튼으로 읽히지 않는다** | CTA가 항상 `paywall.continue` (`PaywallView.swift:239`). 어떤 상품인지, 얼마인지, trial인지 버튼에 없음 | **높음** |
| **B. 7일 무료 체험을 모르고 들어갔다가 StoreKit 시트에서 처음 본다** | `trialText`가 상품 카드 caption에만 있음 `:369`. 구조상 놓치기 쉬움 | **높음** |
| C. 가격 확인 목적으로 눌러본다 | 버튼에 가격이 없으니 눌러야 알 수 있다 | 중간 |
| D. Lifetime/Yearly 사이에서 결정을 못 했다 | Lifetime에 비교 맥락 없음 | 중간 |
| E. StoreKit 시트가 갑자기 나타난다 | 중간 확인 단계 없음 (`purchase()` `:283`이 즉시 `product.purchase()`) | 중간 |
| F. Trial처럼 보이지만 실제 결제다 | Paywall 하단에 "24시간 무료로 써보기"가 따로 있어 두 trial이 혼동될 수 있음 `:186` | **가능성** |
| G. 상품 선택 자체가 불명확 | 기본 선택이 되어 있어 오히려 명확함 | 낮음 |
| H. 지역/결제수단 문제 | 코드로 판별 불가 | 불명 |

**가장 유력: A + B.** 둘 다 버튼 문구 한 줄로 해결 가능한 문제다.

---

## 12. Analytics Gaps

### 12.1 현재 이벤트 존재 여부

| 요구 이벤트 | 코드 존재 | 위치 | 문제 |
|---|---|---|---|
| `pro_template_tapped` | ✅ | `AnalyticsService.swift:271` | — |
| `pro_info_sheet_viewed` | ✅ | `:275` | **`pro_template_tapped`과 같은 줄에서 즉시 발생** |
| `pro_preview_viewed` | ✅ | `:279` | **sheet `onAppear` — 위 둘과 사실상 동시** |
| `pro_preview_interacted` | ✅ | `:283` | **데이터 없는 사용자에게만 가능** |
| `paywall_seen` | ✅ | `:263` | **sheet 표시가 아니라 요청 시점에 로깅** |
| `plan_selected` | **❌ 없음** | — | `ProductCard.onTap`이 상태 대입만 함 `:163` |
| `purchase_started` | ✅ | `:289` | — |
| `purchase_completed` | ✅ | `:303` | — |
| `purchase_cancelled` | ✅ | `:317` | — |
| `purchase_failed` | ✅ | `:323` | — |
| `restore_completed` | ✅ | `:329` | — |
| `temporary_pro_trial_started` | ✅ | `:333` | — |
| `paywall_dismissed` | **❌ 없음** | — | 닫기 이탈을 측정 못 함 |
| `trial_cta_tapped` | **❌ 없음** | — | — |
| `purchase_value_applied` | **❌ 없음** | — | 구매 후 실제 적용 성공 여부 미측정 |

**치명적 발견:** `pro_template_tapped` = `pro_info_sheet_viewed` = `pro_preview_viewed` = **116 events / 38 users** (완전 동일).
이는 세 이벤트가 **같은 하나의 순간**을 세 번 기록하기 때문이다 (`TemplatePickerView.swift:57-60` + `:211`).
**현재 "Pro 탭 → info → preview" 퍼널은 정보량이 0이다.** [C][A]

### 12.2 파라미터 점검

| 파라미터 | 현재 | 비고 |
|---|---|---|
| `template_id` | ✅ pro_* 이벤트 전부 | — |
| `source` / `paywall_trigger` | ✅ | `paywall_seen`은 `source`를 하드코딩 `"app"`으로 넣고 실제 트리거는 `paywall_trigger`에 넣음 — 혼동 소지 `:264` |
| `value` / `currency` | ✅ started/completed | `purchase_cancelled`/`failed`에는 **없음** |
| `plan` (monthly/yearly/lifetime) | **❌** | `product_id`만 있음. GA4에서 `.yealy`/`.yearly` 두 ID가 분리 집계됨 |
| `is_trial` | **❌** | trial 구매와 일반 구매를 구분 불가 |
| `previous_plan` | **❌** | 업그레이드 추적 불가 |
| `paywall_variant` | **❌** | A/B 테스트 불가 |
| `app_version` | ✅ | `commonParameters` `:36` |
| `is_premium` / `days_since_install` | ✅ | `commonParameters` |
| `preview_template` (paywall_seen에) | **❌** | 어떤 템플릿이 Paywall을 유발했는지 모름 |
| `has_photo` / `has_dday` (preview 품질) | **❌** | 빈 미리보기 비율을 측정 못 함 |

### 12.3 GA4 데이터에만 있고 코드에 없는 이벤트 [A][C]

`lockscreen_activity_updated`(605), `widget_timeline_requested`(341), `lockscreen_setup_guide_*`,
`lockscreen_display_method_*`, `paywall_product_selected`(6), `next_day_open`, `notif_permission_*`
— 이들은 **Flutter 빌드 잔재**이고 현재 SwiftUI 코드는 발행하지 않는다.
특히 `paywall_product_selected`는 Flutter에는 있었으나 **SwiftUI 전환에서 유실됐다.**

`first_open`, `session_start`, `screen_view`, `app_update`, `os_update`, `purchase`,
`user_engagement`는 Firebase 자동 수집이다.

---

## 13. 결제 퍼널 정의 및 이탈 지점

### 실제 GA4 기준 퍼널 (사용자 수)

```text
first_open                    71명   ████████████████████  100%
onboarding_start              67명   ███████████████████    94%
onboarding_complete           59명   ████████████████       83%
activation_complete           58명   ████████████████       82%   ← 매우 건강함
live_activity_start_success   60명   ████████████████       85%
lockscreen_preview_seen       68명   ███████████████████    96%
────────────────────────────────────────────────────────────
pro_template_tapped           38명   ██████████             54%   ← Pro 인지
pro_info_sheet_viewed         38명   ██████████             54%   ← 동일 순간 (정보량 0)
pro_preview_viewed            38명   ██████████             54%   ← 동일 순간 (정보량 0)
pro_preview_interacted         1명   ▏                       1%   ← 구조적 사망
paywall_seen                  36명   █████████              51%
purchase_started              10명   ███                    14%   ← ★ 최대 이탈 72%
purchase_cancelled             7명   ██                     10%
purchase_completed             4명   █                       6%   ← 최종 5.2%
```

### 이탈 지점 순위

| 순위 | 구간 | 이탈 | 진단 |
|---|---|---:|---|
| **1** | `paywall_seen` → `purchase_started` | **72%** (36→10) | Paywall이 이유를 못 줌 + CTA가 결제로 안 읽힘 |
| **2** | `purchase_started` → `completed` | **60%** (10→4) | StoreKit 시트에서 기대와 실제가 불일치 (trial/가격) |
| 3 | `activation` → `pro_template_tapped` | 34% (58→38) | Pro 발견 자체는 나쁘지 않음 (54%) |
| 4 | `pro_preview_viewed` → `paywall_seen` | 5% (38→36) | **낮아 보이지만 설득이 아니라 정보 부재로 통과한 것** |

**돈이 죽는 곳은 Paywall과 StoreKit 시트 사이다.** 발견(discovery)은 문제가 아니다. [A][I]

---

## 14. 아이디어 A~H 평가

### A. Annual First — **이미 구현됨. 마감만 필요** ✅

기본 선택(`selectDefaultProduct` `:278`), 최상단 배치(`productRank` `:273`), Best Value 배지(`:333`),
월 환산가(`:402`)가 전부 있다.
**빠진 것은 42% 절약 숫자 하나뿐이다.** `yearlySavingsPercent`와 `paywall.savePercent`가
둘 다 존재하므로 **렌더링 코드 몇 줄이면 끝난다.** → **P0으로 채택.**

### B. Lifetime 가격 조정 — **필요하지만 지금은 아니다** ⚠️

2.21배는 확실히 낮다. 그러나:
- 지금 Paywall 자체가 설득에 실패하고 있어서, 가격을 올리면 원인 분리가 불가능해진다.
- 기존 구매자와 Product ID는 절대 건드리지 않는다는 제약이 있다.

**순서: Paywall/Preview 수정 → 2~4주 데이터 → 그 다음 Lifetime 노출 조정 → 그 다음 가격 실험.**
1단계는 가격이 아니라 **배치**다: Lifetime을 상품 카드 목록에서 빼고 "한 번 결제 옵션 보기" 접힘 영역으로 내린다.
→ **P1으로 채택 (노출 조정만).**

### C. 7-Day Free Trial — **새로 만들 필요 없음. 이미 있다** ✅

App Store Connect에 연간 7일 체험이 구성되어 있고 `freeTrial(for:)`이 읽고 있다.
문제는 **CTA 버튼이 그 사실을 말하지 않는 것**이다.
- trial이 결제율을 올릴지: **예 — 이미 있는 trial을 노출만 해도 오른다.**
- 취소율만 높일지: 초기 취소는 늘 수 있으나, 현재의 69% 즉시 취소보다는 나쁠 수 없다.
→ **P0으로 채택 (노출만, 상품 구성 변경 없음).**

한 가지 보완 필요: `PaywallView.trialText`가 `Product.SubscriptionInfo.isEligibleForIntroOffer`를 확인하지 않는다.
이미 체험을 쓴 사용자에게 "7일 무료"를 보여주면 StoreKit 시트와 불일치한다. → 동시에 수정.

### D. Pro Bundle 강화 — **절반은 가능, 절반은 거짓말** ⚠️

```text
주장하려는 번들:
  고급 템플릿 ✅ 구현됨
+ 이미지      ✅ 구현됨
+ D-Day       ✅ 구현됨
+ 고급 커스터마이징  ❌ ProFeature.cardCustomization이 게이팅 0건 (현재 무료)
+ Unlimited Shortcuts ✅ 구현됨
+ Morning Briefing    ❌ 완전 무료 — 지금 광고 중인 것이 문제
+ iCloud Sync         ❌ 코드 자체가 없음
+ Advanced Dynamic Island ❌ 코드 자체가 없음
```

**없는 것을 번들에 넣는 것은 다크 패턴이자 App Review 리스크다.**
→ **부분 채택:** 있는 것(템플릿·이미지·D-Day·Shortcut·색상)만 하나의 결과 서사로 묶고,
**Morning Briefing 줄은 즉시 제거한다.** → 제거는 **P0**, 번들 재구성은 **P1**.

### E. Contextual Paywall — **이미 설계가 있다. 죽은 트리거를 살리는 게 먼저** ✅

`MonetizationTriggers`와 5개 source가 이미 존재한다. 새로 만들 게 아니라 **연결**하면 된다.
- `offerPaywallForShortcutLimit()` 호출처 연결 → 가장 고의도인 순간
- `first_lock_screen_success` 도달 불가 문제 해결
→ **P1으로 채택.** (Paywall 자체가 설득에 실패하는 동안 노출만 늘리면 역효과이므로 P0 이후)

### F. Pro Preview (실제 사용자 데이터) — **뼈대는 있다. 데이터가 안 채워진다** ✅✅

**이것이 가장 효과 큰 개선이다.** 구조 자체는 이미 실제 데이터 기반이다.
고쳐야 할 것은 세 가지뿐:
1. 이미지 템플릿 미리보기에서 사진을 **미리 고를 수 있게** (`PhotosPicker`는 이미 `LockScreenTabView`에 있다)
2. D-Day 템플릿 미리보기에서 **날짜/제목을 항상 입력 가능하게** (`needsTemporaryPreviewInput` 조건 제거)
3. Memo+Todo 미리보기에서 콘텐츠가 없는 쪽에 **플레이스홀더 예시** 표시
→ **P0으로 채택.**

### G. Trial Preview (조작은 되지만 실제 적용은 제한) — **F와 통합** ✅

F를 구현하면 자연스럽게 달성된다. 미리보기에서 사진을 고르고 D-Day를 넣어 보되,
**잠금화면에는 결제 전까지 적용되지 않는다.** `pendingProTemplate` 메커니즘이 이미 이 패턴을 지원한다
(`AppEnvironment.swift:252`, `:258`). 사진/D-Day도 같은 방식으로 pending 처리하면 된다.
→ **F에 흡수.**

### H. Paywall copy 결과 중심 전환 — **채택, 단 과장 금지** ✅

현재: "잠금화면을 더 나답게" (분위기)
제안 방향: 사용자가 방금 본 결과를 그대로 문장으로 만든다.

```text
제목 (템플릿 맥락 있을 때):
  이 잠금화면을 계속 쓰세요

부제:
  사진, D-Day, 메모+할 일을 잠금화면 한 장에.
  단축어 제한 없이, 앱을 열지 않고.

연간 CTA:
  7일 무료로 시작 · 이후 연 ₩7,700

Lifetime CTA (보조 영역):
  한 번 결제하고 계속 사용
```

주의: "더 많이 보고, 더 빠르게 추가하고"류는 **무료로도 되는 것**이라 오히려 Pro 가치를 흐린다.
Pro는 **"보이는 방식"**이지 **"할 수 있는 양"**이 아니다. → **P0으로 채택.**

---

## 15. User A/B/C 시뮬레이션

### User A — Todo 2~3개만 잠금화면에 보고 싶은 사용자

| 항목 | 내용 |
|---|---|
| 무료로 충분한 부분 | **전부.** Live Activity, 잠금화면 완료, 위젯, 캘린더, 글자 크기까지 |
| 결제 트리거 | **현재 없음.** 이 사용자가 Pro 템플릿을 탭할 이유가 없다 |
| 결제 장애물 | 장애물 이전에 동기가 없다 |
| 추천 Pro 가치 | **이 사용자에게 팔지 마라.** Activation과 리텐션 자산으로 두고, 리뷰·구전 자원으로 활용한다. 억지 Paywall은 이탈만 만든다 |

**Q: 이 사용자는 Pro를 왜 사야 하는가?**
**A: 살 이유가 없다. 그리고 그것이 옳다.** 무료 사용자 전원을 결제시키려는 설계는 activation 82%를 깬다. [I]

### User B — 잠금화면 꾸미기와 이미지/D-Day를 좋아하는 사용자

| 항목 | 내용 |
|---|---|
| 무료로 충분한 부분 | 기본 표시, 날짜 템플릿, 글자 크기/굵기, Light/Dark |
| 결제 트리거 | **사진이 들어간 잠금화면을 실제로 본 순간.** D-Day 숫자가 큰 글씨로 뜬 걸 본 순간 |
| 결제 장애물 | **현재 그 순간이 존재하지 않는다.** 미리보기에 회색 `photo` 심볼만 뜬다 |
| 추천 Pro 가치 | 이미지 템플릿 + D-Day + accent 색상을 **하나의 "내 잠금화면" 서사**로 |

**Q: 언제 결제 욕구가 생기는가?**
**A: 자기 사진이 들어간 자기 할 일 목록을 눈으로 본 직후 3초 안에.**
현재 코드는 이 3초를 **구매 후에** 제공한다. 순서가 뒤집혀 있다. **이것이 P0-1의 근거다.** [C][I]

### User C — Shortcuts / Dynamic Island / 자동화를 많이 쓰는 Power User

| 항목 | 내용 |
|---|---|
| 무료로 충분한 부분 | Dynamic Island 전체, App Intents, 공유 확장, 온보딩의 자동화 3종 가이드, 하루 5회 Shortcut |
| 결제 트리거 | **하루 5회 한도를 넘는 순간** — 유일하게 자연스러운 고의도 순간 |
| 결제 장애물 | **그 순간에 Paywall이 뜨지 않는다.** `offerPaywallForShortcutLimit()` 호출처 없음. Shortcut 응답 문자열만 보고 끝 |
| 추천 Pro 가치 | 무제한 Shortcut + (향후) 고급 Dynamic Island + 여러 D-Day 프리셋 |

**Q: Pro가 충분히 매력적인가?**
**A: 현재는 아니다.** Power User가 살 만한 것은 무제한 Shortcut 하나인데,
그 한도에 걸려도 앱은 아무 제안을 하지 않는다.
GA4에서 `shortcut_quick_add`가 **0건**인 것도 주목할 만하다 — 이 사용자군 자체가 거의 없거나
Shortcut 발견에 실패하고 있다. [A]

---

## 16. 경쟁 앱 관점 [D]

| 축 | Live Note | Live Memo | LockTodoNote | 판단 |
|---|---|---|---|---|
| 무료 범위 | 핵심 기능 무료, 광고 없음을 **반복 약속** | 광고 포함 무료 | 핵심 기능 무료, 광고 없음 | **동급, 우리도 강점** |
| Paywall 시점 | 미확인 | 미확인 | Pro 템플릿 탭 중심 | 우리가 더 맥락적 |
| 광고 | 없음 | **있음** | 없음 | **우리 우위** |
| Customization | 사진 배경, 무제한 색상, 라벨 | 사진·색·투명도·스티커 | 사진·9색·글자 | 경쟁 열위 |
| Live Activity | 지원 | 지원(12h 명시) | 지원(12h) | 동급 |
| Shortcuts | 재실행/가이드 확인 | 미확인 | **App Intents + 공유 확장** | **우리 우위** |
| Widget | Memo/Todo/small | Widget 모드 | **accessoryRectangular/Inline만** | **우리 열위 — Home medium/large 없음** |
| Subscription | ₩2,900/₩17,900 | ₩1,500/₩9,900 | ₩1,100/₩7,700 | **우리 최저가** |
| Lifetime | ₩49,000 | ₩24,000 | ₩17,000 | **우리가 과도하게 쌈** |
| Trial | 미확인 | 미확인 | **연 7일 + 24h 템플릿** | **우리 우위, 단 미노출** |

### LockTodoNote가 더 나은 결제 가치를 만들 수 있는 지점

1. **"광고 없음"을 신뢰 자산으로 전면화.** Live Memo는 광고가 있다. footer에 묻혀 있는
   `paywall.noAds`("광고 없음. 내 할 일은 나만의 것입니다")를 Paywall 상단으로 올릴 가치가 있다.
2. **잠금화면 상호작용 깊이.** 잠금화면에서 직접 완료·날짜 이동·섹션 전환은 경쟁 대비 확실한 강점이다.
   단, 이건 무료 activation 자산이지 Pro 소재가 아니다.
3. **Home Widget medium/large 확장을 Pro 번들에 넣을 수 있다.** 현재 `accessoryRectangular`/`Inline`만
   구현되어 있으므로, Home 화면 대형 위젯 + 사진 템플릿을 Pro로 신설하면
   무료 activation을 전혀 해치지 않으면서 새로운 Pro 가치가 생긴다. (신규 개발)
4. **가격은 건드리지 말고 가치 전달만 고친다.** 이미 최저가인데 팔리지 않는다는 사실 자체가
   문제가 가격이 아님을 증명한다.

**경쟁 앱을 복제하지 않는다.** 특히 광고 모델은 절대 도입하지 않는다 — 현재 최대 차별점을 스스로 없애는 일이다.

---

## 17. P0 개선안 (최대 5개)

### P0-1. Pro Preview에 실제 결과를 채워 넣는다

| 항목 | 내용 |
|---|---|
| **현재 문제** | 이미지 템플릿 미리보기에 사진이 없고(회색 `photo` 심볼), D-Day 미리보기에 날짜가 없다. 입력 필드는 Todo/Memo가 둘 다 없을 때만 뜬다 |
| **사용자 관점 원인** | 사려는 물건의 견본이 빈 상자다. "사진 템플릿"을 눌렀는데 사진이 없다 |
| **구체적 수정** | ① `needsTemporaryPreviewInput`(`TemplatePickerView.swift:258`) 조건을 **템플릿이 요구하는 슬롯 기준**으로 바꾼다 — 이미지 템플릿이면 사진이 없을 때, D-Day 템플릿이면 날짜가 없을 때 입력 UI를 띄운다 ② info sheet 안에 `PhotosPicker`를 넣어 **결제 전에 사진을 골라 미리보기에만 반영**한다 (실제 적용은 `pendingProTemplate`와 같은 방식으로 보류) ③ `previewSnapshot`(`:224`)이 선택한 사진/D-Day를 스냅샷에 주입하도록 확장 ④ Memo+Todo는 빈 pane에 예시 플레이스홀더 |
| **관련 파일** | `LockTodoNote/Features/Templates/TemplatePickerView.swift` (`:128-281`), `LockTodoNote/Features/Home/DashboardPreviewCard.swift` (`PreviewImage`), `LockTodoNote/App/AppEnvironment.swift` (`:252`, `:258`) |
| **예상 효과** | `paywall_seen → purchase_started` 구간(현재 28%)의 개선. **본 보고서에서 가장 효과가 클 것으로 예상되는 단일 개선** |
| **리스크** | 미리보기에서 사진을 고르게 하면 "이미 되네?"로 오해할 수 있다 → 미리보기 하단에 잠금 표식과 "결제 후 잠금화면에 적용됩니다" 명시 필요. 사진 저장은 `LockScreenImageStore`에 실제로 쓰지 말고 메모리 내 미리보기로만 처리 |
| **측정 이벤트** | `pro_preview_interacted(template_id, action: "photo_picked"/"dday_set")`, `pro_preview_viewed(template_id, has_photo, has_dday)` |

### P0-2. CTA 버튼에 상품·가격·무료 체험을 쓴다

| 항목 | 내용 |
|---|---|
| **현재 문제** | 하단 고정 버튼이 언제나 "계속하기" (`PaywallView.swift:239`). trial 표기는 상품 카드 caption에만 있다 |
| **사용자 관점 원인** | "계속하기"는 다음 화면 버튼으로 읽힌다. 탭하면 결제 시트가 튀어나온다 → 놀라서 취소 |
| **구체적 수정** | ① 선택된 상품에 따라 버튼 문구를 동적으로 만든다: trial 있으면 `"7일 무료로 시작 · 이후 연 ₩7,700"`, 없으면 `"₩17,000 한 번 결제"` ② `PurchaseService.freeTrial(for:)`(`:139`)에 `isEligibleForIntroOffer` 확인을 추가해 재구매자에게 잘못된 trial 문구가 뜨지 않게 한다 |
| **관련 파일** | `LockTodoNote/Features/Paywall/PaywallView.swift` (`:233-252`, `:338`), `LockTodoNote/Core/Purchases/PurchaseService.swift` (`:139`), `Localizable.xcstrings` (신규 키 + 9개 언어) |
| **예상 효과** | `purchase_started → completed`(현재 40%) 개선. 취소율 69% → 업계 수준으로 |
| **리스크** | 낮음. 다크 패턴의 반대 방향(정보 공개)이므로 App Review 리스크 없음. 번역 9개 언어 필요 |
| **측정 이벤트** | `purchase_started(is_trial, plan, price, currency)`, `purchase_cancelled(is_trial, plan, price)` |

### P0-3. Paywall 상단에 결과 미리보기를 넣고 Morning Briefing 줄을 제거한다

| 항목 | 내용 |
|---|---|
| **현재 문제** | ① Paywall에 결과 이미지가 전혀 없다 ② "Morning Briefing options"는 **무료 기능**인데 Pro 혜택으로 광고 중이다 (`PaywallView.swift:128`, `SettingsTabView.remindersSection` 게이팅 0건) |
| **사용자 관점 원인** | 가격표만 보인다. 그리고 이미 쓰고 있는 기능을 팔려 하면 나머지 약속도 못 믿게 된다 |
| **구체적 수정** | ① `PaywallRequest`에 `pendingTemplate`를 함께 전달해 Paywall 상단 40%에 **방금 본 Pro 미리보기**를 그대로 렌더 ② `benefits`에서 `paywall.benefit.briefing` 행 삭제 ③ 혜택을 6개 균등 나열 대신 **이미지 1개를 크게 + 나머지 축약**으로 재구성 ④ `paywall.noAds`를 footer에서 상단으로 이동 |
| **관련 파일** | `LockTodoNote/Features/Paywall/PaywallView.swift` (`:75-135`, `:184-217`), `LockTodoNote/App/AppEnvironment.swift` (`PaywallRequest` `:270`, `requestPaywall` `:252`) |
| **예상 효과** | `paywall_seen → purchase_started` 개선. 신뢰 훼손 제거 |
| **리스크** | `PaywallRequest.id`가 현재 `source`다. 템플릿을 추가하면 id 구성 변경 필요 — `.sheet(item:)` 재표시 동작 확인 필요 |
| **측정 이벤트** | `paywall_seen(paywall_trigger, preview_template, has_preview)` |

### P0-4. 연간 42% 절약을 화면에 렌더링한다

| 항목 | 내용 |
|---|---|
| **현재 문제** | `yearlySavingsPercent`(`PurchaseService.swift:120`)와 `paywall.savePercent`("%d%% 절약") 문자열이 **둘 다 존재하는데 UI에서 쓰이지 않는다** |
| **사용자 관점 원인** | 연간이 얼마나 이득인지 사용자가 직접 곱셈해야 한다. 그래서 "그냥 평생 사지"로 간다 |
| **구체적 수정** | 연간 `ProductCard`의 "Best Value" 배지 옆 또는 아래에 `String(format: paywall.savePercent, purchases.yearlySavingsPercent ?? 0)` 렌더. 값이 `nil`이면 미표시 |
| **관련 파일** | `LockTodoNote/Features/Paywall/PaywallView.swift` (`:333`, `ProductCard` `:356-420`) |
| **예상 효과** | plan mix를 Lifetime → Yearly로 이동. LTV 개선 |
| **리스크** | 매우 낮음. 이미 계산 로직과 번역이 준비되어 있어 렌더링만 추가 |
| **측정 이벤트** | `plan_selected(plan, product_id, price, is_default)` — P0-5와 함께 |

### P0-5. plan_selected 이벤트를 추가하고 pro_* 중복 이벤트를 정리한다

| 항목 | 내용 |
|---|---|
| **현재 문제** | ① `plan_selected`가 없어 상품 선택 행동을 전혀 측정 못 한다 (Flutter에는 `paywall_product_selected`가 있었으나 유실) ② `pro_template_tapped`/`pro_info_sheet_viewed`/`pro_preview_viewed`가 **같은 순간에 3번 로깅**되어 116/116/116로 완전히 동일하다 (`TemplatePickerView.swift:57-60`) |
| **사용자 관점 원인** | (측정 문제) — 어디서 왜 떨어지는지 모르면 다음 개선을 고를 수 없다 |
| **구체적 수정** | ① `ProductCard.onTap`(`PaywallView.swift:163`)에 `analytics.planSelected(...)` 추가 ② `pro_info_sheet_viewed` 제거 또는 실제로 다른 순간(스크롤/체류)에 재정의 ③ `paywall_seen`을 `requestPaywall` 시점이 아니라 **`PaywallView.task`** 시점으로 이동 ④ 모든 purchase_* 이벤트에 `plan`, `is_trial` 파라미터 추가 (`ProductIdentifiers.Kind`로 `.yealy`/`.yearly` 통합) ⑤ `paywall_dismissed(plan_selected_at_dismiss)` 신설 |
| **관련 파일** | `LockTodoNote/Core/Analytics/AnalyticsService.swift` (`:263-327`), `LockTodoNote/Features/Paywall/PaywallView.swift` (`:163`, `:57`), `LockTodoNote/Features/Templates/TemplatePickerView.swift` (`:57-60`), `LockTodoNote/Features/Home/LockScreenTabView.swift` (`:211`) |
| **예상 효과** | 직접 매출 효과 0. 그러나 **P0-1~4의 효과를 측정할 수 없으면 다음 사이클이 불가능하다** |
| **리스크** | 기존 이벤트 **이름은 절대 바꾸지 않는다** (`AnalyticsService` 상단 주석의 원칙 유지). 파라미터 추가와 신규 이벤트만 |
| **측정 이벤트** | 이 항목 자체가 측정 개선 |

---

## 18. P1 / P2 / Do Not Do

### P1

| # | 개선안 | 근거 | 파일 |
|---|---|---|---|
| P1-1 | **`offerPaywallForShortcutLimit()` 호출처 연결** | 호출처 0건 (`AppEnvironment.swift:158`). 가장 고의도인 순간을 버리고 있다. Intent가 App Group에 플래그를 남기고 앱 포그라운드 시 Paywall | `AppEnvironment.swift`, `GlanceCardAppIntents.swift:34`, `AppGroupKeys.swift` |
| P1-2 | **Lifetime을 보조 위치로 이동** | 2.21배 회수로 Yearly 잠식. 가격은 그대로 두고 **접힘 영역 "한 번 결제 옵션"** 으로 내림 | `PaywallView.swift:142`, `:273` |
| P1-3 | **구매 직후 성공 경험 추가** | 현재 `applyPendingProTemplate()` + `dismiss()`가 전부. Live Activity 재시작 + 적용 결과 확인 화면 | `PaywallView.swift:290`, `AppEnvironment.swift:258` |
| P1-4 | **24시간 체험 CTA 승격 및 문구 구분** | 3명만 사용. 연 7일 trial과 혼동 소지. "Pro 템플릿 24시간 체험(결제 없음)"으로 명확화 후 info sheet로 이동 | `PaywallView.swift:186`, `TemplatePickerView.swift:128` |
| P1-5 | **Pro 번들 재구성 (있는 것만)** | Morning Briefing/iCloud/고급 Island 제외. 템플릿·이미지·D-Day·Shortcut·색상을 하나의 결과 서사로 | `PaywallView.swift:91`, `Localizable.xcstrings` |
| P1-6 | **`first_lock_screen_success` 도달성 복구** | 자동 시작이 선점해 사실상 도달 불가. `ensureLiveActivityStarted()`의 **첫 성공**에도 트리거를 태우되 soft teaser로 | `AppEnvironment.swift:128`, `:170` |
| P1-7 | **`cardCustomization` / `displayStyle` 케이스 정리** | 선언만 있고 게이팅 0건. 실제로 게이팅하거나 enum에서 제거 | `CardEnums.swift:130` |

### P2

| # | 개선안 | 근거 |
|---|---|---|
| P2-1 | Home Widget medium/large + 사진 템플릿 → 새 Pro 가치 | 현재 `accessoryRectangular`/`Inline`만. 경쟁 열위이자 신규 Pro 소재 |
| P2-2 | 다중 D-Day 프리셋 | 현재 슬롯 1개 (`LockScreenSettings.ddayTitle` 단일 필드). 반복 사용 가치 |
| P2-3 | 템플릿 프리셋 저장/전환 | Power User 대상 반복 가치 |
| P2-4 | `paywall_variant` 파라미터 + A/B 인프라 | 16장 테스트 계획의 전제 |
| P2-5 | Lifetime 가격 실험 (신규 cohort 한정) | P1-2 데이터 확보 후 |
| P2-6 | iCloud Sync 실제 구현 | Pro 번들 강화. 개발 비용 큼 |

### Do Not Do

| 하지 말 것 | 이유 |
|---|---|
| **가격 인하** | 이미 3개 상품 전부 경쟁 최저가. 팔리지 않는 이유가 가격이 아님이 데이터로 확인됨 |
| **무료 Todo/Memo 개수 제한** | activation 82%를 직접 파괴. 이 앱의 최대 자산 |
| **기본 Live Activity를 Pro로 전환** | 앱의 존재 이유 자체. 설치 즉시 이탈 |
| **잠금화면 Todo 완료를 Pro로** | 경쟁 대비 최대 강점을 스스로 제거 |
| **Paywall 노출 빈도 증가를 1차 해법으로** | Paywall이 설득에 실패하는 상태에서 빈도만 늘리면 이탈·리뷰 악화만 발생 |
| **광고 도입** | Live Memo 대비 최대 차별점(광고 없음) 상실 |
| **닫기 버튼 지연 / 가격 은폐 / 강제 시청** | 다크 패턴. App Review 리스크 및 현재 코드의 정직함 훼손 |
| **미구현 기능(iCloud Sync, 고급 Dynamic Island)을 Paywall에 광고** | 허위 광고. Morning Briefing 건은 지금 즉시 제거 대상 |
| **Product ID 변경** | `.yealy` 오타 포함 현행 ID 유지 필수. 기존 구독자 전원 손실 |
| **기존 이벤트 이름 변경** | 기존 대시보드 분절. 파라미터 추가만 허용 |

---

## 19. Free / Pro 재설계 (권장 최종 구조)

### Free — 절대 건드리지 않는다 (activation 자산)

```text
✅ Todo / Memo 무제한 생성·편집·삭제
✅ Live Activity (12시간, 자동 복구)
✅ Dynamic Island 전체 (minimal / compact / expanded)
✅ 잠금화면에서 직접 Todo 완료
✅ 기본 위젯 (accessoryRectangular / Inline)
✅ Calendar 전체
✅ 기본 템플릿 2종 (Calendar+항목, 날짜+항목)
✅ Privacy 모드 4종
✅ 글자 크기 / 굵기
✅ Light / Dark / System
✅ 아침·저녁 알림 (Morning Briefing)
✅ Shortcut 하루 5회
✅ 공유 확장 링크 저장
✅ 광고 없음
```

### Pro — "내 잠금화면을 내가 만든다"

```text
🔒 사진 템플릿 (이미지 + Todo / 이미지 + Memo)   ← 주력
🔒 D-Day 카운트다운 템플릿                        ← 보조 주력
🔒 Memo + Todo 동시 레이아웃
🔒 Accent 색상 9종
🔒 Shortcut 무제한
◻︎ (P2) Home Widget medium/large + 사진
◻︎ (P2) 다중 D-Day / 템플릿 프리셋
```

### Paywall에서 삭제할 것

```text
❌ "Morning Briefing options"  — 무료 기능. 즉시 제거
❌ iCloud Sync                 — 미구현. 언급 금지
❌ Advanced Dynamic Island     — 미구현. 언급 금지
```

**원칙:** 무료는 "오늘을 잠금화면에서 본다"를 완결한다.
Pro는 "그 잠금화면이 내 것처럼 보인다"를 판다.
기능의 **양**이 아니라 **보이는 방식**이 경계선이다.

---

## 20. Paywall 재설계 (권장 화면 흐름)

```text
Pro 템플릿 탭
  ↓
[Pro Preview — 개선]
  ├─ 실제 내 Todo/Memo가 들어간 잠금화면 미리보기
  ├─ 사진 템플릿이면 → 여기서 사진을 골라 미리보기에 즉시 반영 (적용은 보류)
  ├─ D-Day 템플릿이면 → 여기서 날짜/제목 입력해 미리보기에 즉시 반영
  ├─ 하단 잠금 표식: "결제 후 잠금화면에 적용됩니다"
  ├─ 부가: "Pro 템플릿 24시간 체험 (결제 없음)"     ← P1-4
  └─ CTA: "이 잠금화면 사용하기"
       ↓
[Paywall — 개선]
  ├─ 상단 40%: 방금 만든 그 미리보기를 그대로            ← P0-3
  ├─ 제목: "이 잠금화면을 계속 쓰세요"
  ├─ 부제: 사진 · D-Day · 메모+할 일 · 무제한 단축어
  ├─ 신뢰 배지: "광고 없음 · 내 할 일은 나만의 것"
  ├─ [연간  ₩7,700]  Best Value · 42% 절약 · 월 ₩642   ← P0-4, 기본 선택
  ├─ [월간  ₩1,100]
  ├─ ▸ 한 번 결제 옵션 보기 (접힘)                       ← P1-2
  │     └─ [평생 ₩17,000]
  ├─ CTA: "7일 무료로 시작 · 이후 연 ₩7,700"            ← P0-2
  ├─ 자동 갱신 고지 / Restore / 약관 / 개인정보
  └─ X 닫기 (즉시, 지연 없음)                            ← 현행 유지
       ↓
[구매 성공 — 개선]
  ├─ 선택한 템플릿 + 사진/D-Day 즉시 적용                ← P1-3
  ├─ Live Activity 재시작
  └─ "잠금화면을 확인해 보세요" 확인 화면
```

---

## 21. Pricing Recommendation

| 상품 | 현재 | 권장 (1단계) | 권장 (2단계, 데이터 후) |
|---|---:|---|---|
| Monthly ₩1,100 | 노출 2위 | **변경 없음** | 변경 없음 |
| Yearly ₩7,700 | 기본 선택 | **변경 없음 + 42% 절약 표기 추가** | 변경 없음 |
| Lifetime ₩17,000 | 카드 3위 | **접힘 영역으로 이동 (가격 동결)** | 신규 cohort에서 ₩24,000 실험 |

**핵심 원칙 3가지**

1. **가격을 내리지 않는다.** 이미 경쟁 최저가다. 가격이 병목이라는 증거가 없다.
2. **Product ID와 기존 구매자를 건드리지 않는다.** `.yealy` 오타 ID를 포함해 현행 유지.
3. **가격 변경보다 노출 변경이 먼저다.** Lifetime은 가격을 올리기 전에 **배치를 내린다.**
   두 변수를 동시에 바꾸면 원인을 분리할 수 없다.

### Trial 필요 여부

**새로 만들 필요 없음. 이미 두 개가 있고 둘 다 안 보인다.**

| Trial | 현재 상태 | 조치 |
|---|---|---|
| 연간 7일 무료 체험 (StoreKit) | 구성됨, 상품 카드 caption에만 표시 | **CTA 버튼 전면으로 (P0-2)** + `isEligibleForIntroOffer` 확인 추가 |
| 24시간 Pro 템플릿 체험 (자체) | Paywall 하단 plain 링크, 3명만 사용 | **Pro Preview 안으로 이동 + "결제 없음" 명시 (P1-4)** |

---

## 22. A/B Test Plan

전제: `paywall_variant` 파라미터 인프라 (P2-4).
**한 번에 한 변수만.** 현재 표본(월 77명)에서는 순차 실험만 유효하다.

| # | 변수 | A (현행) | B (실험) | 1차 지표 | 2차 지표 | 최소 기간 |
|---|---|---|---|---|---|---|
| T1 | CTA 문구 | "계속하기" | "7일 무료로 시작 · 이후 연 ₩7,700" | `purchase_started → completed` | `purchase_cancelled` 비율 | 4주 |
| T2 | Pro Preview 완성도 | 현행 빈 미리보기 | 사진/D-Day 입력 가능 | `paywall_seen → purchase_started` | `pro_preview_interacted` 비율 | 4주 |
| T3 | Paywall 상단 미리보기 | 없음 | 결과 미리보기 40% | `paywall_seen → purchase_started` | 체류 시간 | 4주 |
| T4 | Lifetime 배치 | 카드 3위 노출 | 접힘 영역 | Yearly 선택 비율 | 전체 `purchase_completed` | 6주 |
| T5 | 42% 절약 표기 | 없음 | Best Value 옆 표기 | Yearly 선택 비율 | — | 4주 |
| T6 | Shortcut 한도 Paywall | 없음 (사망) | 한도 도달 시 Paywall | `paywall_seen(shortcut_limit_reached)` 전환율 | Shortcut 사용 유지율 | 6주 |

**주의:** 표본이 작다. T4/T6은 신규 cohort로만 돌리고, 기존 구매자 cohort와 반드시 분리한다.

---

## 23. Success Metrics

| 지표 | 현재 (GA4) | 1차 목표 | 산식 |
|---|---:|---:|---|
| Activation rate | **82%** (58/71) | **유지 (≥80%)** | `activation_complete` / `first_open` |
| Pro feature tap → Preview | 100% (측정 무의미) | 이벤트 재정의 후 재측정 | `pro_preview_viewed` / `pro_template_tapped` |
| Preview 상호작용률 | **1%** (1/38) | **≥ 35%** | `pro_preview_interacted` / `pro_preview_viewed` |
| Preview → Paywall | 95% (36/38) | 유지 | `paywall_seen` / `pro_preview_viewed` |
| **Paywall → Purchase Started** | **28%** (10/36) | **≥ 40%** | `purchase_started` / `paywall_seen` |
| **Purchase Started → Completed** | **40%** (4/10) | **≥ 60%** | `purchase_completed` / `purchase_started` |
| 취소율 | **69%** (9/13) | **≤ 45%** | `purchase_cancelled` / `purchase_started` |
| Plan mix (Yearly 비중) | 미측정 | **≥ 55%** | `plan_selected` 기준 |
| D7 Paid Conversion | 미측정 | 기준선 수립 | 설치 후 7일 내 `purchase_completed` 사용자 / cohort |
| D30 Paid Conversion | 미측정 | 기준선 수립 | 설치 후 30일 내 동일 |
| 전체 결제 전환율 | **5.2%** (4/77) | **≥ 8%** | `purchase_completed` / `first_open` |
| ARPU | **$0.09** (7.00/77) | **≥ $0.30** | 총수익 / 총 사용자 |

---

## 24. Final Recommendation

### 1. 지금 구독이 거의 없는 가장 큰 이유 한 가지

**Pro의 결과를 결제 전에 한 번도 보여주지 않기 때문이다.**

"사진 템플릿"을 탭하면 사진이 없는 회색 placeholder가 뜨고, "D-Day"를 탭하면 날짜 없는 "D-Day" 글자가 뜬다.
Paywall에는 결과 이미지가 아예 없다. 사용자는 **자기 잠금화면이 어떻게 달라지는지 본 적이 없는 상태로**
₩7,700을 요구받는다. 가격도, 기능 수도, 트리거 빈도도 아니다. **가치 전달의 실패다.**

### 2. 무료 기능이 너무 강한가?

**강하다. 그러나 줄이면 안 된다.**
무료가 앱의 존재 이유를 100% 충족하는 건 사실이다. 하지만 activation 82%는 이 앱의 최대 자산이고,
무료를 줄이면 다운로드가 그대로 이탈로 바뀐다. 해법은 무료 축소가 아니라 **Pro 가치의 신설과 전달**이다.

### 3. Pro 기능이 너무 약한가?

**약하다. 특히 번들의 절반이 실체가 없다.**
- 실제 게이팅: 템플릿 4종 + accent 색상 + Shortcut 한도 = **6개**
- `ProFeature`에 선언만 되고 게이팅 0건: `cardCustomization`, `displayStyle` = **2개 사문화**
- 코드 자체가 없음: iCloud Sync, Advanced Dynamic Island
- **무료인데 Pro로 광고 중: Morning Briefing** ← 즉시 제거 필요

팔 수 있는 진짜 물건은 사실상 **이미지 템플릿 하나**다. 그것을 제대로 보여주는 게 먼저다.

### 4. 가격 구조 문제 여부

**구독 가격은 문제 없다. Lifetime 비율만 문제다.**
₩1,100 / ₩7,700 / ₩17,000은 세 상품 모두 경쟁 최저가다.
문제는 Lifetime이 Yearly의 **2.21배**(회수 2.2년)라 장기 구독을 구조적으로 잠식하는 것이다.
단, **1차 조치는 가격 인상이 아니라 노출 하향**이다.

### 5. Paywall 문제 여부

**예. 두 번째로 큰 문제다.**
- 결과 미리보기 없음
- CTA가 "계속하기" — 결제 버튼으로 읽히지 않음 → 취소율 69%
- 42% 절약 숫자가 코드에 계산되어 있는데 화면에 없음
- 혜택 6줄 중 1줄이 사실과 다름

칭찬할 점도 명확하다: **닫기 즉시 노출, 전 가격 공개, 광고 없음 약속. 다크 패턴이 없다. 이건 지켜야 한다.**

### 6. Lifetime 가격 문제 여부

**예. 2.21배는 낮다. 권장 3~5배.**
다만 지금 Paywall 자체가 설득에 실패 중이므로 **가격을 먼저 만지면 원인 분리가 불가능하다.**
순서: Paywall/Preview 수정 → 2~4주 데이터 → Lifetime 배치 하향 → 그 다음 신규 cohort 가격 실험.

### 7. Trial 필요 여부

**새 trial은 필요 없다. 있는 trial 두 개를 보이게 하면 된다.**
연간 7일 무료 체험은 App Store Connect에 이미 있고 코드도 읽고 있다. 버튼에 올리기만 하면 된다.
24시간 템플릿 체험은 Paywall 하단 plain 링크라 3명만 썼다. Pro Preview 안으로 옮기고 "결제 없음"을 명시한다.

### 8. 가장 먼저 바꿀 P0 5개

| # | 개선안 | 한 줄 요약 |
|---|---|---|
| **P0-1** | Pro Preview에 실제 결과 채우기 | 결제 전에 사진/D-Day를 넣어 본인 잠금화면을 보게 한다 |
| **P0-2** | CTA에 상품·가격·무료 체험 명시 | "계속하기" → "7일 무료로 시작 · 이후 연 ₩7,700" |
| **P0-3** | Paywall 상단 결과 미리보기 + Morning Briefing 줄 제거 | 가격 화면을 가치 화면으로, 거짓 약속 제거 |
| **P0-4** | 연간 42% 절약 렌더링 | 이미 계산된 값을 화면에 표시만 하면 된다 |
| **P0-5** | `plan_selected` 추가 + 중복 pro_* 이벤트 정리 | 측정이 안 되면 다음 사이클이 불가능하다 |

### 9. 절대 하지 말아야 할 변경

1. **가격 인하** — 이미 최저가. 팔리지 않는 이유가 가격이 아님이 데이터로 증명됨
2. **무료 Todo/Memo 개수 제한** — activation 82%를 직접 파괴
3. **기본 Live Activity / 잠금화면 완료를 Pro로 전환** — 앱의 존재 이유와 최대 강점
4. **Paywall 빈도 증가를 1차 해법으로 삼기** — 설득 실패 상태에서 빈도만 늘리면 이탈·리뷰 악화
5. **광고 도입** — Live Memo 대비 최대 차별점 상실
6. **닫기 지연 / 가격 은폐 등 다크 패턴** — 현재 코드의 정직함을 훼손, App Review 리스크
7. **미구현 기능(iCloud Sync, 고급 Dynamic Island) 광고** — 허위 광고
8. **Product ID 변경** — `.yealy` 오타 포함 현행 유지 필수. 기존 구독자 전원 손실
9. **기존 Firebase 이벤트 이름 변경** — 대시보드 분절. 파라미터 추가만 허용

### 10. 가장 효과가 클 것으로 예상되는 개선 1개

> **P0-1 — Pro Preview에 사용자 본인의 사진과 D-Day를 넣어, 결제 전에 완성된 잠금화면을 직접 보게 한다.**

이유:
- 최대 이탈 구간(`paywall_seen → purchase_started`, **72% 이탈**)의 직접 원인을 제거한다
- 구조가 이미 실제 사용자 데이터 기반이다. **새로 만드는 게 아니라 비어 있는 슬롯을 채우는 작업**이다
- User B(꾸미기 선호)의 결제 트리거인 "내 사진이 들어간 내 할 일"을 **결제 후가 아니라 결제 전에** 제공한다
- 무료 activation을 전혀 건드리지 않는다
- 가격 변경도, Product ID 변경도, 기존 구매자 영향도 없다

---

## 부록 A. 코드 위치 색인

| 관심사 | 파일:라인 |
|---|---|
| Product ID / Entitlement / ProFeature 판정 | `Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Models/ProductIdentifiers.swift:10`, `:48`, `:88` |
| ProFeature enum (8 case, 2개 사문화) | `Packages/.../Models/CardEnums.swift:130` |
| 템플릿 → ProFeature 매핑 | `Packages/.../Models/CardEnums.swift:108` |
| StoreKit 구매 / 복원 / entitlement | `LockTodoNote/Core/Purchases/PurchaseService.swift:49`, `:88`, `:152`, `:198` |
| 연간 절약률 (미사용) | `LockTodoNote/Core/Purchases/PurchaseService.swift:120` |
| 24시간 임시 체험 | `LockTodoNote/Core/Purchases/PurchaseService.swift:209-247` |
| Paywall 트리거 정의 | `LockTodoNote/Core/Purchases/MonetizationTriggers.swift` |
| Paywall 화면 전체 | `LockTodoNote/Features/Paywall/PaywallView.swift` |
| Paywall 혜택 6줄 (1줄 허위) | `LockTodoNote/Features/Paywall/PaywallView.swift:91-133` |
| Paywall CTA "계속하기" | `LockTodoNote/Features/Paywall/PaywallView.swift:233-252` |
| 연간 기본 선택 / 정렬 | `LockTodoNote/Features/Paywall/PaywallView.swift:273`, `:278` |
| Pro Preview (info sheet) | `LockTodoNote/Features/Templates/TemplatePickerView.swift:128-281` |
| Preview 스냅샷 구성 (슬롯 미충전) | `LockTodoNote/Features/Templates/TemplatePickerView.swift:224` |
| 입력 UI 조건 (역전됨) | `LockTodoNote/Features/Templates/TemplatePickerView.swift:258` |
| 사진 placeholder 렌더 | `LockTodoNote/Features/Home/DashboardPreviewCard.swift` (`PreviewImage`) |
| Today 탭 템플릿 선택 | `LockTodoNote/Features/Home/LockScreenTabView.swift:158`, `:203`, `:209` |
| Paywall 요청 / 템플릿 보류 적용 | `LockTodoNote/App/AppEnvironment.swift:252`, `:258` |
| 죽은 트리거 (Shortcut 한도) | `LockTodoNote/App/AppEnvironment.swift:158` |
| 도달 불가 트리거 (첫 성공) | `LockTodoNote/App/AppEnvironment.swift:128`, `:170` |
| Paywall 시트 표시 | `LockTodoNote/App/RootView.swift:37` |
| Settings Pro 카드 / 색상 게이팅 | `LockTodoNote/Features/Settings/SettingsTabView.swift:138`, `:569` |
| Morning Briefing (게이팅 0건) | `LockTodoNote/Features/Settings/SettingsTabView.swift:78-90` |
| Shortcut 하루 5회 한도 | `Extensions/WidgetExtension/GlanceCardAppIntents.swift:34`, `Packages/.../AppGroup/AppGroupKeys.swift:42` |
| 분석 이벤트 전체 | `LockTodoNote/Core/Analytics/AnalyticsService.swift:263-335` |
| 위젯 isPremium (analytics 전용) | `Extensions/WidgetExtension/GlanceCardLockScreenWidget.swift:432` |

## 부록 B. 참고 문서

- `docs/competitor-analysis-live-note-live-memo.md` — 경쟁 앱 실기기 분석, 실제 가격, 11장 결제 개선안
- 본 보고서는 그 문서의 11장 결론(가격 인하 금지, preview 중심 전환)과 일치하며, 코드 레벨 근거를 추가한 것이다.
