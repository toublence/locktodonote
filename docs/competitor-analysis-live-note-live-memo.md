# LockTodoNote 경쟁앱 실기기 분석 및 개선 계획

분석일: 2026-08-21  
분석 대상: Live Note 1.3.8, Live Memo 1.3.4, LockTodoNote SwiftUI 전환 코드  
문서 상태: **분석 및 계획만 완료 — 구현 승인 전**

## 관찰 근거 표기

- **[D] 직접 관찰**: USB로 연결한 실제 iPad 화면에서 확인
- **[S] 공개 정보**: App Store 앱 설명, 스크린샷, 버전 기록, 가격
- **[C] 코드 확인**: 현재 LockTodoNote 소스에서 확인
- **[I] 판단**: 위 사실을 바탕으로 한 제품/UX 판단
- **미확인**: 실제 조작이나 공개 정보만으로 확정할 수 없음

이 구분 없이 경쟁앱의 내부 구현을 추측하지 않는다.

---

## 1. Executive Summary

1. **최신 iOS UI 격차는 실제로 존재한다.** Live Memo는 최소 iOS/iPadOS 26을 요구하고, 플로팅 원형 툴바·Liquid Glass 형태의 세그먼트·하단 상태 캡슐을 제품 구조 자체로 사용한다. Live Note도 시스템 시트와 플로팅 컨트롤을 최신 디자인과 결합한다. 반면 LockTodoNote는 `NavigationStack`, `TabView`, `Form`의 자동 최신화 이점은 받지만, 핵심 화면 대부분이 불투명한 커스텀 카드와 테두리로 구성되어 일관된 iOS 26 인상을 만들지 못한다.
2. **LockTodoNote는 기술적 기반이 뒤처진 앱이 아니다.** 현재 코드에는 Live Activity, Dynamic Island의 minimal/compact/expanded, 잠금화면 Todo 완료, 날짜 전환, Memo/Todo 전환, Quick Add 딥링크, App Intents, 정적 잠금화면 위젯이 이미 있다. 상호작용 범위는 경쟁앱과 동급이거나 더 강하다.
3. **가장 큰 제품 격차는 기능 수보다 ‘한 화면에서 바로 쓰고 결과를 보는 흐름’이다.** Live Note와 Live Memo는 앱 첫 화면이 곧 편집기이자 잠금화면 미리보기다. LockTodoNote는 추가 버튼 → Todo/Memo 선택 → 별도 Sheet → 저장의 구조여서 핵심 가치가 한 단계 멀다.
4. **Live Memo의 가장 강한 장점은 iOS 26 네이티브 인상과 세 가지 지속 채널이다.** `월페이퍼 / 라이브 / 위젯`을 같은 콘텐츠의 전달 방식으로 보여주기 때문에 Live Activity가 끝나도 대안이 있다는 사실을 쉽게 이해시킨다.
5. **Live Note의 가장 강한 장점은 직접 편집, 다중 입력, 생태계 연결이다.** 여러 줄 붙여넣기 자동 Todo 분리, Apple 미리알림 연동, Widget, Dynamic Island, 공유 확장 링크 저장이 공개 정보로 확인된다.
6. **LockTodoNote가 이미 더 잘하는 핵심은 잠금화면 상호작용과 프라이버시다.** `ToggleTodoIntent`, `SelectDateIntent`, `SelectContentSectionIntent`, 네 가지 프라이버시 모드, 두 개의 공개 App Shortcut은 코드로 확인된다.
7. **Static Widget fallback은 ‘있음’이 아니라 ‘부분 구현’이다.** 현재 정적 위젯은 `.accessoryRectangular`, `.accessoryInline`만 지원한다. Home Screen medium/large와 인터랙티브 완료가 없어 Live Activity 종료 뒤 핵심 콘텐츠를 유지하는 역할이 약하다.
8. **낮은 결제율을 가격 인하로 해결하면 안 된다.** 국내 가격은 LockTodoNote가 이미 월 1,100원/연 7,700원/평생 17,000원으로 두 경쟁앱보다 낮다. 문제는 가격보다 Pro 결과 미리보기, 잠금 기능의 맥락, 구매 직후 얻는 변화가 약한 것이다.
9. **최신 UI 적용은 ‘모든 카드에 유리 효과 추가’가 아니다.** Apple 지침대로 Liquid Glass는 탐색·컨트롤의 기능 레이어에 제한하고, 메모·Todo 카드 같은 콘텐츠 레이어는 표준 material과 명확한 계층을 사용해야 한다. 그렇지 않으면 가독성과 성능이 나빠진다.
10. **다음 업데이트의 P0는 5개다.** iOS 26 adaptive shell, 한 화면 Quick Capture, Live Activity 수명/재시작 UX, Home Widget fallback, 결과 중심 Pro Preview/Paywall이다.

---

## 2. Test Environment

### 2.1 실기기 연결 결과

| 항목 | 확인 결과 |
|---|---|
| Device name | `iPad (4)` [D] |
| Model | iPad Air 11-inch (M2), `iPad14,8` [D] |
| OS | iPadOS 26.6, build `23G71` [D] |
| 연결 | USB wired, paired, connected [D] |
| Developer Mode | Enabled [D] |
| 화면 관찰 | QuickTime Player 입력 소스로 실시간 관찰 가능 [D] |
| 앱 실행 | `devicectl`로 Bundle ID 지정 실행 가능 [D] |
| Mac에서 터치 조작 | 불가. 화면 미러링은 관찰 전용 [D] |
| 스크린 캡처 | QuickTime 미러링 화면 캡처 및 App Store 스크린샷 확인 가능 [D/S] |

### 2.2 앱 식별

| 앱 | Display Name | Bundle ID | 개발자/제공자 | 버전 |
|---|---|---|---|---|
| Live Note | LiveNote / 라이브노트 | `mjkoo.livenote` | LVNT | 1.3.8 |
| Live Memo | LiveMemo / 라이브메모 | `com.madeuse.LiveMemo` | Yeonwoo Lee / MADEUSE | 1.3.4 |
| LockTodoNote | LockTodoNote | `com.namslab.glancecard` | ChangHyun Nam / NamsLab | 코드 1.2.0 (14), 스토어 1.1.3 |

### 2.3 분석 방식

- 실제 기기에서 두 경쟁앱을 Bundle ID로 직접 실행하고 현재 저장 상태의 메인 화면을 관찰했다.
- 기존 사용자 데이터를 삭제하거나 앱을 재설치하지 않았다.
- App Store 설명, iPad/iPhone 스크린샷, 버전 기록, IAP 가격을 교차 확인했다.
- LockTodoNote는 현재 SwiftUI 소스, Widget Extension, App Intents, StoreKit, Firebase 이벤트 코드를 직접 읽었다.
- Apple의 iOS 26 디자인 가이드와 SwiftUI API 문서를 확인했다.

### 2.4 직접 확인하지 못한 영역

- Mac에서 iPad로 터치 이벤트를 전달할 수 없어 경쟁앱의 모든 메뉴를 끝까지 조작하지 못했다.
- 기존 데이터를 보존했으므로 최초 설치 온보딩을 실제로 재현하지 않았다.
- 결제 승인, 구독 시작, 복원은 실행하지 않았다.
- iPad에는 Dynamic Island가 없어 경쟁앱 Dynamic Island 실물 상태는 확인하지 못했다.
- 잠금화면 편집 화면에서 Widget family 전체 목록과 Shortcuts 앱의 action 수를 끝까지 확인하지 못했다.
- 따라서 아래 표에서 확정할 수 없는 항목은 `미확인`으로 표기한다.

실기기 분석은 **연결·앱 식별·현재 메인 UI 관찰에는 성공**, 전체 터치 플로우 재현에는 **부분 성공**이다.

---

## 3. Live Note 분석

### 3.1 첫 인상과 핵심 사용자 흐름

**[D]** 실행 직후 큰 검은 편집 카드, `LIVE` 상태와 남은/경과 시간, Memo/Todo 전환, 사진·링크·캘린더 옵션이 한 화면에 보였다. 메모 내용이 이미 입력되어 있었고 Live Activity가 실행 중인 상태였다.

**[S]** App Store iPad 스크린샷에서는 첫 안내가 2페이지형 모달로 보이며, “잠금화면에서 바로 작성”과 잠금화면 미리보기를 먼저 설명한다. 실제 최초 설치의 정확한 터치 수는 미확인이다.

대표 흐름:

```text
앱 실행
→ 큰 편집 영역에 바로 입력
→ Memo/Todo 또는 일정 모드 선택
→ LIVE 상태에서 잠금화면 반영 확인
```

이 흐름의 강점은 “목록 화면을 찾은 뒤 항목을 추가”하는 일반 Todo 앱 구조가 아니라, **첫 화면 자체가 현재 잠금화면 콘텐츠의 편집기**라는 점이다.

### 3.2 Top 10 Strengths

1. 첫 화면에서 바로 메모를 입력하고 현재 Live 상태를 확인한다. [D]
2. Live Activity와 Dynamic Island를 모두 핵심 설명에 포함한다. [S]
3. Todo 생성·체크·수정·순서 변경을 지원한다. [S]
4. 여러 줄 붙여넣기를 줄 단위 Todo로 자동 분리한다. [S]
5. Apple 미리알림 연동과 주간 캘린더/일정 모드를 제공한다. [S]
6. 메모/Todo 위젯과 small Todo 위젯을 지속적으로 개선했다. [S]
7. 공유 시트에서 링크를 저장하고 카테고리·검색·썸네일을 제공한다. [S]
8. 핵심 기능 무료·광고 없음이라는 신뢰 메시지가 명확하다. [S]
9. 사진 배경, 무제한 색상, 라벨 편집처럼 눈에 보이는 개인화를 Pro로 묶었다. [S]
10. 4.9점, 약 1.4천 평가와 빠른 피드백 반영 기록이 제품 신뢰를 만든다. [S]

### 3.3 Top 10 Weaknesses

1. 메모·Todo·사진·링크·캘린더가 한 화면에 모여 핵심 입력이 점점 복잡해질 위험이 있다. [D/I]
2. 상단 아이콘 전환과 일부 원형 버튼은 라벨이 없어 첫 사용자에게 의미가 불명확할 수 있다. [D/I]
3. 최신 시스템 글래스 컨트롤과 큰 검은 커스텀 카드가 섞여 시각 언어가 이중적이다. [D/I]
4. iPad에서 편집 카드가 매우 넓어 긴 행의 가독성과 포인터 이동 거리가 커진다. [D/I]
5. 링크 보관은 유용하지만 잠금화면 Todo/Memo 핵심에서 제품 범위를 넓힌다. [S/I]
6. Live Activity는 iOS 수명 제한을 피할 수 없어 재실행/새로고침 학습이 필요하다. [S]
7. 일정·링크·커스터마이징이 추가되며 “단순한 앱” 메시지와 충돌할 수 있다. [S/I]
8. 정확한 Free/Pro 경계가 App Store 설명만으로 한눈에 보이지 않는다. [S]
9. 접근성 지원 항목을 App Store에 별도로 등록하지 않았다. [S]
10. 월 2,900원/연 17,900원/평생 49,000원은 강한 가치 설명 없이 보면 진입 장벽이 될 수 있다. [S/I]

### 3.4 잠금화면 / Dynamic Island / Widget

- Live Activity로 Memo와 Todo를 잠금화면에 표시한다. [S]
- 수정 즉시 잠금화면에 반영한다고 설명한다. [S]
- 일정이 있으면 남은 시간을 표시한다. [S]
- Dynamic Island 지원과 Todo 모드 개선 기록이 있다. [S]
- Memo/Todo Widget, small Todo Widget이 있다. [S]
- “Live Activity 종료 시 Widget이 fallback인가?”에 대한 답: **구조적으로 가능성이 높지만 실제 자동 전환은 미확인**. Widget이 별도 존재하는 것은 확인되지만 자동 fallback 동작은 확인하지 못했다.

### 3.5 Todo / Memo / Shortcuts

| 기능 | 확인 결과 |
|---|---|
| Todo 생성/완료/수정/순서 변경 | 지원 [S] |
| 여러 줄 자동 분리 | 지원 [S] |
| 완료 목록/히스토리 | 지원 기록 [S] |
| 아이콘 | 지원 [S] |
| 알림/리마인더 | 지원 [S] |
| Apple 미리알림 연동 | 지원 [S] |
| Memo 즉시 편집 | 메인 화면에서 확인 [D] |
| Shortcut 재실행/가이드 | 지원 기록 [S] |
| Shortcut action 수/Siri phrase | 미확인 |
| 앱을 열지 않고 추가 | Shortcut/공유 확장 흐름 존재 [S] |

### 3.6 결제

App Store 국내 가격:

- 월간 2,900원
- 연간 17,900원
- Lifetime 49,000원

확인된 Pro 가치:

- 사진 배경
- 무제한 색상
- 라벨 편집
- 일정 모드 등 확장 기능

페이월 최초 등장 시점, 닫기 버튼 지연, trial의 실제 구성은 미확인이다. 다만 “핵심 기능 무료, 광고 없음”을 반복해서 먼저 약속하고 개인화/확장 기능에 과금하는 구조는 신뢰에 유리하다.

### 3.7 리텐션

- 잠금화면 반복 노출 자체가 앱 실행 없이 리텐션을 만든다.
- Todo 완료, 캘린더 일정, D-Day, 리마인더, 위젯이 일별 사용 이유를 만든다.
- 공유 링크 저장은 빈도 높은 capture loop를 만든다.
- 버전 기록과 리뷰 답변에서 사용자 피드백 반영 속도가 커뮤니티 리텐션에 기여한다.

### 3.8 UI/UX — 가장 좋은 UI 5개

1. `LIVE` 상태와 지속 시간을 메인 상단에 상시 표시한다. [D]
2. 큰 편집 카드를 중심에 두어 “지금 보이는 내용이 잠금화면에 간다”는 대응 관계가 명확하다. [D]
3. Memo/Todo 모드 전환이 편집 카드 가까이에 있다. [D]
4. 공유 Sheet의 카테고리 pill과 Save/Cancel이 iPadOS 26 시스템 표현을 사용한다. [S]
5. 잠금화면 미리보기를 온보딩에서 결과 중심으로 보여준다. [S]

### 3.9 UI/UX — 개선이 필요한 UI 5개

1. 메인 화면 옵션 수가 늘어 현재 행동 우선순위가 흐려진다. [D/I]
2. 아이콘 전용 버튼의 의미가 즉시 드러나지 않는다. [D/I]
3. 검은 편집 카드의 고정 스타일은 Light/Dark 및 iPadOS 26 material과 자연스럽게 연결되지 않는다. [D/I]
4. iPad에서 지나치게 넓은 한 장 카드보다 편집/미리보기 2열이 효율적이다. [D/I]
5. 링크 보안 잠금 등 중첩된 Sheet는 작업 맥락을 잃게 할 수 있다. [S/I]

---

## 4. Live Memo 분석

### 4.1 첫 인상과 핵심 사용자 흐름

**[D]** 실행 직후 중앙 상단에 `월페이퍼 / 라이브 / 위젯` 세그먼트, 좌측 history, 우측 `…`, 큰 노란 메모 카드, 하단 `Live · 자동` 상태 캡슐이 보였다. iPadOS 26의 플로팅 시스템 컨트롤을 전면에 사용한다.

대표 흐름:

```text
앱 실행
→ 전달 방식(월페이퍼/라이브/위젯) 선택
→ 화면 상단 카드에서 콘텐츠 확인/편집
→ 하단 상태로 현재 Live 동작 확인
```

최초 설치 온보딩과 정확한 터치 수는 미확인이다.

### 4.2 Top 10 Strengths

1. 최소 iOS/iPadOS 26을 요구하며 최신 디자인 시스템을 일관되게 사용한다. [D/S]
2. 월페이퍼·Live Activity·Widget을 같은 콘텐츠의 세 가지 전달 방식으로 설명한다. [D/S]
3. 플로팅 history/ellipsis/segmented/status 컨트롤의 계층이 명확하다. [D]
4. 메모 카드가 잠금화면 결과와 시각적으로 거의 동일하다. [D/S]
5. 큰 콘텐츠 미리보기 덕분에 설정 결과를 즉시 이해한다. [D]
6. 체크리스트를 잠금화면에서 바로 완료할 수 있다는 사용자 리뷰가 있다. [S]
7. 사진 배경, 사용자 색상, 투명도, 스티커 등 시각 개인화 가치가 분명하다. [S]
8. 앱 크기가 작고 제품 설명도 단순하다. [S]
9. 15개 언어와 iPhone/iPad/Mac을 지원한다. [S]
10. 월 1,500원/연 9,900원/평생 24,000원으로 Plus 선택 구조가 단순하다. [S]

### 4.3 Top 10 Weaknesses

1. 실기기 메인 화면 하단에 광고 배너가 보여 집중과 프리미엄 인상을 해친다. [D]
2. App Store 개인정보 표시에 광고 추적/기기 식별자/사용 데이터가 포함된다. [S]
3. iPad에서 메모 카드 아래의 큰 빈 공간을 활용하지 못한다. [D]
4. 밝은 단색 배경과 투명도 조합은 대비 기준을 깨뜨릴 가능성이 있다. [D/S/I]
5. 세 가지 모드는 이해하기 쉽지만 각각의 차이와 제한을 화면만 보고 완전히 알기 어렵다. [D/I]
6. App Store 설명이 “간편한 사용, 최대 12시간” 수준으로 짧아 기능 발견성이 낮다. [S]
7. Live Activity가 최대 12시간이라는 한계를 제품 설명에서 먼저 드러낸다. [S]
8. Dynamic Island와 Shortcuts 지원 여부가 공개 설명에서 확인되지 않는다. [S]
9. 설정과 Pro 진입이 `…` 안에 숨었을 가능성이 높아 발견성이 낮다. [D/I]
10. 접근성 지원 항목을 App Store에 별도로 등록하지 않았다. [S]

### 4.4 잠금화면 / Dynamic Island / Widget

- Live Activity 최대 12시간을 명시한다. [S]
- 잠금화면에 메모와 체크리스트를 표시한다. [S]
- 사용자가 잠금화면에서 체크했다고 쓴 리뷰가 있다. [S]
- Wallpaper, Live, Widget을 모두 지원한다. [D/S]
- App Store iPad 스크린샷은 잠금화면 노란 카드와 앱 내 노란 카드의 일관성을 보여준다. [S]
- Dynamic Island: **미확인**
- Widget family, Interactive Widget 여부: **미확인**
- “Live Activity 종료 시 Widget이 fallback인가?”에 대한 답: **제품 구조상 가장 명확한 fallback 메시지를 제공하지만 자동 전환 여부는 미확인**. 세 모드를 같은 레벨로 노출한 점은 LockTodoNote가 참고할 가치가 있다.

### 4.5 Todo / Memo / Shortcuts

| 기능 | 확인 결과 |
|---|---|
| Memo 작성/표시 | 지원 [D/S] |
| 체크리스트 | 지원 [S] |
| 잠금화면 완료 | 사용자 리뷰로 확인 [S] |
| 사진 배경/사용자 색상 | 지원 [S] |
| 배경 투명도/스티커 | 지원 [S] |
| 알림 | 과거 버전 기록에 존재 [S] |
| 반복/우선순위/순서 변경 | 미확인 |
| Shortcuts/App Intents/Siri | 미확인 |
| 이미지/첨부 | 사진 배경은 확인, 일반 첨부는 미확인 |

### 4.6 결제

App Store 국내 가격:

- 월간 1,500원
- 연간 9,900원
- Lifetime 24,000원

광고가 무료/유료 경계의 일부로 보인다. 정확한 Plus unlock 목록, trial, 페이월 최초 시점은 미확인이다.

### 4.7 리텐션

- 잠금화면, 위젯, 월페이퍼 세 채널이 Live Activity 수명 종료 뒤에도 시각적 접점을 유지한다.
- history 버튼은 과거 메모 재사용 가능성을 높인다.
- 배경·스티커·투명도는 기능 리텐션보다 정서적 개인화 리텐션을 만든다.
- 반면 광고는 반복 사용 시 이탈 요인이 될 수 있다.

### 4.8 UI/UX — 가장 좋은 UI 5개

1. 상단 중앙의 iOS 26 세그먼트가 제품의 세 가지 전달 방식을 즉시 설명한다. [D]
2. history와 `…`가 서로 떨어진 플로팅 원형 컨트롤로 배치되어 역할이 명확하다. [D]
3. 메모 카드가 앱 미리보기와 잠금화면에서 동일한 색·모양을 유지한다. [D/S]
4. 하단 Live 상태 캡슐이 현재 상태를 지속적으로 보여준다. [D]
5. 탐색/컨트롤은 glass, 콘텐츠는 불투명 카드로 분리한다. [D]

### 4.9 UI/UX — 개선이 필요한 UI 5개

1. 광고 배너가 제품의 가장 중요한 하단 상태 영역과 경쟁한다. [D]
2. iPad의 넓은 화면을 카드 하나와 빈 공간으로 소비한다. [D]
3. 카드 안의 편집 가능 영역과 단순 미리보기 영역이 시각적으로 구분되지 않는다. [D/I]
4. 단색 카드의 대비는 사용자 지정 색상에서 자동 보정이 필요하다. [S/I]
5. 핵심 기능 외 설정이 `…`에 몰리면 discoverability가 떨어진다. [D/I]

---

## 5. 경쟁앱 비교

| 항목 | Live Note | Live Memo | 우위 |
|---|---|---|---|
| 핵심 입력 | 큰 직접 편집기 | 큰 카드 직접 편집/미리보기 | Live Note |
| 최신 iOS 26 UI | 시스템 UI + 커스텀 화면 | iOS 26 전용, 전면 적용 | Live Memo |
| Todo 깊이 | 수정·순서·다중 붙여넣기·알림 | 체크리스트 중심 | Live Note |
| Memo 개인화 | 사진·색상·라벨 | 사진·색상·투명도·스티커 | Live Memo |
| Calendar | 주간 일정, 우선순위, Reminders | 확인되지 않음 | Live Note |
| Live Activity | 지원 | 지원, 최대 12시간 명시 | 동급 |
| Dynamic Island | 지원 | 미확인 | Live Note |
| Widget | Memo/Todo/small | Widget 모드 | Live Note(확인 범위) |
| Wallpaper | 미확인 | 지원 | Live Memo |
| Shortcuts | 재실행/가이드 확인 | 미확인 | Live Note |
| 공유 확장 | 링크 저장/카테고리 | 미확인 | Live Note |
| 광고 | 없음 | 있음 | Live Note |
| privacy 인상 | 진단만, 광고 없음 | 광고 추적 데이터 표시 | Live Note |
| 가격 | 2,900/17,900/49,000 | 1,500/9,900/24,000 | Live Memo 진입가 |
| App Store 신뢰 | 4.9, 약 1.4천 평가 | 4.7, 38 평가 | Live Note |
| 다국어 | 6개 | 15개 | Live Memo |

### 두 앱을 합친 이상적 제품

```text
Live Note의 직접 입력·Todo 깊이·Shortcuts·Calendar
+ Live Memo의 iOS 26 UI·월페이퍼/Live/Widget 채널 표현·시각 미리보기
- Live Note의 기능 과밀
- Live Memo의 광고·큰 빈 공간·얕은 정보 구조
= 잠금화면 중심의 빠르고 아름다운 일일 capture/complete 앱
```

LockTodoNote가 이 조합보다 좋아지려면 **한 화면 입력**, **Live Activity보다 오래 남는 interactive fallback**, **잠금화면에서 날짜·Todo·Memo 처리**, **Morning Briefing**을 한 제품 언어로 연결해야 한다.

---

## 6. LockTodoNote 현재 상태

### 6.1 기술/프로젝트

| 항목 | 코드 확인 결과 |
|---|---|
| UI | SwiftUI 전환 코드. 원래 Flutter 저장 형식 마이그레이션 포함 |
| Xcode | 로컬 Xcode 26.1.1 |
| Minimum OS | 앱/Widget iOS 16.1, Share iOS 16.0 |
| Branch | `main`, 아직 commit 없음 |
| Git 상태 | 전체 프로젝트가 untracked 상태 |
| Architecture | `AppEnvironment`가 Store/Service/Coordinator 주입 |
| Storage | App Group JSON + UserDefaults, atomic write |
| App Group | `group.com.namslab.glancecard` |
| Firebase | FirebaseAnalytics + Crashlytics package 연결 |
| StoreKit | StoreKit 2 current entitlements + transaction updates |
| Localization | en/ko/ja/es/hi/de/fr/zh-Hans/zh-Hant |
| Sync | CloudKit/iCloud 동기화 없음 |

### 6.2 화면/기능 구조

- `RootView.swift`: Lock Screen / Calendar / Settings 3-tab.
- `LockScreenTabView.swift`: Live Activity 상태, Template, Image, D-Day, Todo, Memo.
- `CalendarTabView.swift`: 월 그리드 + 선택 날짜 Todo/Memo.
- `QuickAddSheet.swift`: Todo/Memo 입력, Todo 반복.
- `TemplatePickerView.swift`: 7개 템플릿, Pro info sheet.
- `OnboardingView.swift`: 5단계, 첫 Todo → preview → Live Activity 활성화.
- `PaywallView.swift`: 월/연/평생, 연간 기본 선택, savings, trial 표시.
- `SettingsTabView.swift`: privacy, text, shortcuts, morning/evening reminder, theme, saved links, legal.

### 6.3 잠금화면/Widget/App Intents

- `GlanceCardLiveActivity.swift`
  - Lock Screen Live Activity
  - Dynamic Island minimal/compact/expanded
  - Todo 완료
  - Memo/Todo 탭 전환
  - 날짜 선택
  - quick memo/todo 딥링크
- `GlanceCardLockScreenWidget.swift`
  - `.accessoryRectangular`, `.accessoryInline`
  - 날짜·Todo·Memo fallback
  - Home Screen family 및 interactive action 없음
- `GlanceCardAppIntents.swift`
  - 공개 Shortcut 2개: Add to LockTodoNote, Refresh Lock Screen
  - 앱 열지 않고 실행
  - 한국어/영어 Siri phrase
  - Live Activity 내부 Intent 3개

### 6.4 Todo/Memo 데이터 기능

- Todo 생성/완료/삭제, daily/weekdays/weekly 반복.
- 미완료 Todo 다음 날 rollover.
- 모델에 `dueDate`, `icon`이 있으나 현재 Quick Add UI에서는 노출하지 않는다.
- Todo 편집/순서 변경 UI가 없다.
- 여러 줄 입력은 한 Todo 문자열로 저장되어 Live Note보다 불리하다.
- Memo 생성/수정/삭제/날짜/핀을 지원한다.
- 한 개의 pinned memo만 잠금화면 대표로 사용한다.
- 일반 이미지 첨부가 아니라 템플릿 배경 이미지 용도다.

### 6.5 결제/리뷰/분석

- StoreKit product: monthly/yearly/lifetime.
- 현재 국내 스토어 가격: 월 1,100원, 연 7,700원, 평생 17,000원.
- 연간 상품의 7일 무료 체험이 App Store Connect에 구성되어 있다는 실가격 확인 기록이 있다.
- 별도 24시간 Pro template preview도 있다.
- paywall trigger: 첫 잠금화면 성공, day 2, trial 만료, Shortcut 한도, Pro 기능 탭.
- review request: 첫 성공 이후 다음 적절한 성공 시 1회.
- Firebase 이벤트는 onboarding, activation, Todo, Live Activity, Shortcut, paywall, purchase, widget queue까지 존재한다.
- `memo_created`, `widget_interaction`, `core_active_user`, `briefing_completed`는 없다.

### 6.6 현재 UI 진단

좋은 점:

- 표준 `NavigationStack`, `TabView`, `Form`, `toolbar`, `sheet`를 써서 iOS 26 SDK로 빌드하면 시스템 부분은 자동으로 최신 외형을 얻는다.
- semantic palette와 Light/Dark/9 accent가 분리되어 있다.
- Dynamic Type에 유리한 SwiftUI Text, Label, Form을 사용한다.
- 주요 interactive 요소에 accessibility label/traits가 일부 적용되어 있다.

격차:

- `glassEffect`, `.buttonStyle(.glass)`, `GlassEffectContainer` 사용이 0건이다.
- 주요 버튼이 `RoundedRectangle + background + foreground` 커스텀으로 시스템 press/morph 반응을 얻지 못한다.
- 홈/캘린더/템플릿/페이월에 16~18pt 불투명 카드와 border가 반복되어 시각 계층이 평평하다.
- iPad에서 핵심 화면을 최대 720pt 단일 컬럼으로 제한해 화면을 충분히 쓰지 못한다.
- iPad용 `NavigationSplitView`, sidebar, pointer/keyboard shortcut 설계가 없다.
- Quick Add가 별도 Sheet여서 Live Note/Live Memo처럼 “보이는 것을 바로 편집”하지 못한다.
- Paywall은 기능 목록과 상품 카드 중심이며, 구매 후 실제 잠금화면이 어떻게 달라지는지 강한 preview가 없다.

---

## 7. 기능 비교 및 Gap Analysis

| 기능 | Live Note | Live Memo | LockTodoNote | 가장 좋은 구현 | LockTodoNote 조치 |
|---|---|---|---|---|---|
| Todo | 수정·순서·다중 붙여넣기 | 체크리스트 | 생성·완료·삭제·반복 | Live Note | 인라인 편집/정렬/줄 분리 |
| Memo | 직접 편집 | 직접 카드 | Sheet 편집/핀 | 경쟁앱 | 홈 인라인 capture |
| Calendar | 주간 일정/우선순위 | 미확인 | 월간 + 날짜별 내용 | Live Note/Lock 혼합 | iPad 2열, 주간은 P2 |
| Lock Screen | Live Activity | Live Activity | Live Activity + 풍부한 template | LockTodoNote | 현재 강점 유지 |
| Live Activity | 지원 | 최대 12h | 12h stale, refresh | LockTodoNote | 수명 UX 개선 |
| Dynamic Island | 지원 | 미확인 | minimal/compact/expanded + action | LockTodoNote | Polish만 |
| Widget | Memo/Todo/small | Widget 모드 | accessory 2종 | Live Note | Home medium fallback |
| Interactive Action | Todo 체크 | 잠금화면 체크 리뷰 | 완료/날짜/섹션 | LockTodoNote | 유지·측정 강화 |
| Shortcut | 재실행/가이드 | 미확인 | Add/Refresh 2개 | LockTodoNote | Memo/Todo action 분리 고려 |
| Siri | 미확인 | 미확인 | 영/한 phrase | LockTodoNote | phrase onboarding |
| Image | Live Activity 배경 | 사진 배경 | Image template | 동급 | preview 품질 향상 |
| D-Day | 지원 | 미확인 | D-Day + Memo | LockTodoNote | 무료 preview 강화 |
| Theme | 무제한 색상 Pro | 색/투명도/스티커 | 9 accent Pro | Live Memo | 자동 대비, glass tint |
| Notification | Todo/Reminders | 과거 알림 | morning/evening | Live Note | item reminder P1 |
| Morning Routine | 확인 안 됨 | 확인 안 됨 | 단순 reminder만 | 없음 | Morning Briefing 차별화 |
| Sync | 명시 불명확 | 미확인 | 없음 | 미확인 | P2 검토 |
| Paywall | core free/no ads | ads + Plus | 기능목록/24h preview | Live Note 신뢰 | 결과 preview 중심 |
| Subscription | 월/연 | 월/연 | 월/연 | 동급 | 연간 기본 유지 |
| Lifetime | 49,000 | 24,000 | 17,000 | 경쟁앱 가격 기준 | 가격 인하 금지, 테스트 |
| Review | 1.4천/4.9 | 38/4.7 | 평가 없음 | Live Note | 성공 순간 개선 |
| Onboarding | 2-page screenshot | 미확인 | 5단계 | 판단 보류 | 3단계로 압축 |
| iPad | 풀 화면이나 과밀 | 최신 UI, 빈 공간 | 720pt 단일 컬럼 | 혼합 | adaptive 2열/sidebar |
| Accessibility | 등록 없음 | 등록 없음 | 코드 label 일부 | LockTodoNote | contrast/motion/transparency QA |

### 7.1 경쟁앱에는 있고 LockTodoNote에는 없는 것

- 여러 줄 Todo 자동 분리
- Todo 텍스트 수정과 순서 변경 UI
- Apple Reminders 연동
- Home Screen Widget family
- Wallpaper 전달 방식
- iOS 26을 제품 전체에서 체감시키는 플로팅 control layer
- Live Memo의 스티커/투명도, Live Note의 주간 일정/링크 카테고리 확장

### 7.2 LockTodoNote에는 있고 경쟁앱에서 확인되지 않은 것

- Live Activity에서 날짜 전환
- Live Activity 안에서 Memo/Todo 섹션 전환
- 네 가지 잠금화면 privacy mode
- refresh App Intent
- 정적 accessory fallback의 tomorrow timeline 준비
- D-Day/Memo, Calendar/Items 등 7개 템플릿
- rollover와 반복 Todo
- Morning/Evening local reminder
- Flutter 데이터 보존 마이그레이션

### 7.3 둘 다 있지만 경쟁앱이 더 좋은 것

- 앱 첫 화면의 직접 입력
- iPadOS 26 컨트롤과 콘텐츠의 시각적 계층
- 현재 Live 상태의 상시 표시
- Pro 개인화 결과의 가시성
- 여러 전달 방식(월페이퍼/Live/Widget) 설명

### 7.4 둘 다 있지만 LockTodoNote가 더 좋은 것

- 잠금화면 interactive action 범위
- Dynamic Island 정보 구조
- privacy와 redaction
- App Intents가 앱을 열지 않고 optimistic update 수행
- 템플릿과 날짜 기반 dashboard 합성
- StoreKit entitlement 검증과 extension analytics queue

---

## 8. 가져와야 할 기능

### 8.1 최신 iOS 26 control layer — COPY CONCEPT / P0

- 경쟁앱: Live Memo는 플로팅 history/settings, glass segmented picker, bottom status capsule을 쓴다.
- 좋은 이유: 앱이 iOS 전용 제품이라는 신뢰를 3초 안에 만든다.
- 그대로 복제하면 안 되는 부분: 세그먼트 위치/색/형태를 복제하지 않는다. 메모 카드 자체까지 glass로 만들지 않는다.
- LockTodoNote 구현 방향:
  - 표준 `TabView`, `NavigationStack`, `NavigationSplitView`, `toolbar`, `Form`, `sheet`의 커스텀 배경을 줄인다.
  - iOS 26에서 Quick Capture, Live 상태, 핵심 플로팅 action에만 `.glass`/`.glassProminent` 또는 `glassEffect`를 사용한다.
  - 여러 glass 버튼은 `GlassEffectContainer`로 묶는다.
  - iOS 16~25에서는 `.ultraThinMaterial`/표준 bordered button fallback을 제공한다.
  - Reduce Transparency, Increase Contrast, Reduce Motion을 반드시 검사한다.
- Free/Pro: UI shell 전체 무료.

### 8.2 한 화면 Quick Capture — IMPROVE / P0

- 경쟁앱: 메인 카드가 편집기다.
- 좋은 이유: 추가 버튼을 찾고 Sheet를 여는 단계를 제거한다.
- 개선안:
  - Home 하단 또는 `tabViewBottomAccessory`에 Todo/Memo segmented capture를 둔다.
  - 입력 즉시 저장 또는 명확한 Done 한 번으로 완료한다.
  - 줄바꿈 붙여넣기는 Todo 여러 개로 preview한 뒤 한 번에 저장한다.
  - 날짜 기본값은 오늘, 필요할 때만 calendar popover.
  - 기존 `QuickAddSheet`는 깊은 옵션(반복/날짜)용으로 유지한다.
- Free/Pro: 기본 capture 무료, Shortcut 무제한만 Pro.

### 8.3 Live 상태와 수명 UX — IMPROVE / P0

- 경쟁앱: Live Note/Live Memo 모두 메인에 현재 Live 상태를 상시 표시한다.
- 문제: LockTodoNote는 상태 카드가 있지만 “몇 시까지/왜 종료/다음 대안” 연결이 약하다.
- 개선안:
  - `활성 · 오늘 21:00까지`, `새로고침 필요`, `Widget은 계속 표시됨` 상태를 한 줄로 제공.
  - `Refresh Lock Screen` App Shortcut을 상태 카드에서 설치/실행 안내.
  - stale일 때 Stop/Start 용어 대신 `다시 시작` 단일 CTA.
  - Live Activity가 없을 때 Home Widget 설치 CTA를 같은 위치에 표시.
- Free/Pro: 무료 핵심 기능.

### 8.4 Static Widget fallback — COPY CONCEPT + DIFFERENTIATE / P0

- 경쟁앱: 별도 Widget 채널이 존재한다.
- 현재: LockTodoNote는 accessory만 있다.
- 개선안:
  - `.systemSmall`, `.systemMedium` 우선 추가.
  - medium에 오늘 날짜, 남은 Todo 3개, pinned Memo, D-Day를 표시.
  - iOS 17+ AppIntent button으로 Todo 완료.
  - Live Activity 종료 시 앱에서 `위젯은 계속 오늘 내용을 보여줍니다` 안내.
  - timeline stale와 app refresh 필요 상태를 시각적으로 구분.
- Free/Pro: 기본 fallback 무료, 사진/고급 template만 Pro.

### 8.5 결과 중심 Pro Preview — IMPROVE / P0

- 경쟁앱: 개인화 결과가 앱 메인에서 바로 보인다.
- 현재: LockTodoNote는 feature list가 먼저다.
- 개선안:
  - 사용자의 실제 Todo 1개와 Memo 일부를 넣은 잠금화면 preview를 paywall 상단에 표시.
  - Pro 템플릿 선택 시 전체 결과를 영구 적용하지 않고, preview 일부를 선명하게 보여주고 나머지는 잠금 처리.
  - `사진 + 오늘 Todo`, `D-Day + Memo`를 탭 전환으로 비교.
  - CTA는 `7일 무료로 이 잠금화면 사용`처럼 결과와 trial을 연결.
  - 구매 후 선택한 template을 즉시 적용하고 Live Activity를 갱신.
- Free/Pro: preview 무료, 적용 Pro.

### 8.6 Todo 인라인 편집/순서 변경 — COPY CONCEPT / P1

- Live Note의 검증된 편의 기능이다.
- `TodoRowView`에 context menu 또는 swipe action으로 Edit, drag reorder를 추가한다.
- `ChecklistItem.icon`, `dueDate`는 모델에 있으므로 UI만 연결하되 기본 입력은 복잡하게 만들지 않는다.

### 8.7 Apple Reminders 연동 — COPY CONCEPT / P1

- 양방향 sync부터 시작하지 않는다.
- 1차는 `Reminders에서 오늘 항목 가져오기` 또는 `LockTodoNote Todo를 Reminders로 보내기` 한 방향.
- 권한과 중복, 완료 동기화 위험이 있으므로 별도 phase와 telemetry가 필요하다.

---

## 9. 버려야 할 기능

### 9.1 스티커 편집기 — IGNORE

- Live Memo에는 정서적 가치가 있지만 별도 canvas/editor/asset 관리가 필요하다.
- LockTodoNote의 “빠르게 보고 추가하고 처리” 정체성과 맞지 않는다.
- 사진 template와 accent만으로 충분한 개인화를 제공한다.

### 9.2 Wallpaper 생성 중심 제품 — IGNORE

- 정적 Wallpaper는 자동 갱신과 상호작용이 약하다.
- Live Activity/Widget fallback을 개선하는 편이 핵심 가치에 직접적이다.
- 향후 Shortcut 기반 wallpaper export는 P3 실험으로만 검토한다.

### 9.3 링크 아카이빙 확장 — IGNORE/단순화

- 현재 Saved Links/Share Extension은 유지할 수 있지만 핵심 탭으로 키우지 않는다.
- 링크 카테고리·썸네일·검색·잠금까지 경쟁하면 별도 제품이 된다.
- Settings 아래 보조 기능으로 유지하고 핵심 onboarding/paywall에서 제외한다.

### 9.4 모든 화면에 Liquid Glass — DO NOT BUILD

- Apple도 content layer에 glass 남용을 권장하지 않는다.
- Todo, Memo, Calendar 셀은 읽기 콘텐츠이며 clear glass보다 standard material/solid surface가 적합하다.
- glass는 navigation, quick action, transient control에만 쓴다.

### 9.5 광고 기반 무료 모델 — DO NOT BUILD

- Live Memo 실기기에서 광고가 메인 집중을 방해했다.
- LockTodoNote는 잠금화면 콘텐츠와 프라이버시를 다루므로 광고 추적은 신뢰 비용이 크다.
- 무료 사용량 제한 + Pro 가치 구조를 유지한다.

---

## 10. 차별화 기능

### 10.1 Morning Briefing — DIFFERENTIATE / P1

```text
알람 중단 Personal Automation
→ 현재 날씨(Shortcuts 시스템 action)
→ LockTodoNote의 오늘 Todo/Memo/D-Day 읽기
→ 음성으로 말하기
```

- 앱이 알람 종료를 직접 감지하거나 자동화를 몰래 생성할 수는 없다.
- LockTodoNote는 `Get Today Briefing` App Intent와 설치 가이드를 제공한다.
- 경쟁앱 공개 정보에서 같은 통합 흐름은 확인되지 않았다.
- Pro 후보: custom briefing 구성/여러 routine. 기본 오늘 요약은 무료가 activation에 유리하다.

### 10.2 Interactive Live Activity 완성도 — DIFFERENTIATE / 이미 강점

- Todo 완료뿐 아니라 날짜 선택, Memo/Todo 전환까지 현재 코드에 있다.
- 다음 단계는 기능 추가보다 discoverability, haptic, 완료 애니메이션, telemetry다.

### 10.3 Live → Widget continuity — DIFFERENTIATE / P0

- Live Activity 만료 시 “사라짐”이 아니라 Widget로 계속 보이는 continuity를 제품 언어로 만든다.
- 앱 Home의 상태, Widget install, Refresh Shortcut을 하나의 lifecycle로 묶는다.

### 10.4 Privacy-aware glance — DIFFERENTIATE / 기존 강점

- full/title only/hidden/count only를 onboarding preview에서 실제로 비교한다.
- 경쟁앱의 밝은 메모 카드보다 “누가 화면을 볼 수 있는가”를 명확히 다룬다.

---

## 11. 결제 개선안

### 11.1 현재와 개선 후

| 항목 | 현재 | 개선 후 |
|---|---|---|
| 첫 가치 | 온보딩 mock preview | 실제 사용자 Todo가 들어간 live preview |
| 첫 upsell | 첫 잠금화면 성공 후 full paywall | 성공 후 soft teaser, 명시적 Pro intent에서 full paywall A/B |
| Pro 설명 | 기능 목록 | 선택한 잠금화면 결과 중심 |
| preview | Pro info sheet 텍스트 | 적용 전 interactive/cropped preview |
| trial | 24h template preview + 연간 7일 trial | 차이를 명확히 설명, 연간 CTA에 7일 trial 전면 노출 |
| plan | 월/연/평생 | 연간 기본, Lifetime은 보조 위치 |
| 구매 후 | dismiss | 선택 template 적용 + Live Activity refresh + success animation |

### 11.2 가격 판단

| 앱 | 월간 | 연간 | Lifetime |
|---|---:|---:|---:|
| LockTodoNote | 1,100원 | 7,700원 | 17,000원 |
| Live Memo | 1,500원 | 9,900원 | 24,000원 |
| Live Note | 2,900원 | 17,900원 | 49,000원 |

결론:

- 가격 인하 금지. 이미 가장 낮다.
- 먼저 preview → paywall → purchase funnel을 고친다.
- 연간은 월간 12회 대비 약 42% 절약이므로 기본 선택을 유지한다.
- Lifetime이 연간의 약 2.2배라 장기 구독을 잠식할 수 있다. 즉시 변경하지 말고 새 사용자 cohort에서 24,000원 또는 Lifetime 비강조를 실험한다.
- 가격 실험 전에 기존 구매자와 StoreKit product ID를 변경하지 않는다.

### 11.3 Free/Pro 재구성

Free:

- Todo/Memo 무제한 기본 입력
- 기본 3개 template
- Live Activity, Dynamic Island, 기본 Widget
- 잠금화면 Todo 완료
- Shortcut 하루 5회
- 기본 privacy와 1개 accent

Pro:

- 사진/D-Day/Memo+Todo template
- 모든 accent, custom text/background
- Shortcut 무제한
- Home Widget 고급 layout 및 사진 template
- Morning Briefing custom 구성
- 향후 Reminders/sync의 고급 옵션

무료 사용자를 막아 핵심 가치를 못 보게 하지 않는다. 사용자가 **실제로 잠금화면 성공을 경험한 뒤** 개인화와 반복 자동화에 비용을 지불하게 한다.

### 11.4 Paywall 카피 제안

제목:

> 오늘 화면을 내 방식으로 유지하세요

부제:

> 사진, D-Day, Memo + Todo, 무제한 빠른 추가를 잠금화면 한 장에.

연간 CTA:

> 7일 무료로 이 잠금화면 사용

Lifetime CTA:

> 한 번 구매하고 계속 사용

### 11.5 필수 이벤트

- `pro_preview_viewed(template_id, source)`
- `pro_preview_interacted(template_id, action)`
- `paywall_seen(paywall_trigger, preview_template)`
- `plan_selected(product_id)`
- `trial_cta_tapped(product_id)`
- `purchase_started/completed/cancelled/failed`
- `purchase_value_applied(template_id, live_refresh_success)`

---

## 12. 리텐션 개선안

### Day 0

- 첫 Todo 입력과 실제 Live Activity 활성화를 3단계 안에 완료.
- 성공 뒤 잠금화면 확인 방법과 Widget fallback을 한 화면에서 안내.
- 앱 실행 리텐션보다 `activation_complete`를 우선 본다.

### Day 1

- 첫 Todo 완료 후 “내일도 이 화면 유지”를 제안.
- Morning reminder 또는 Widget 설치 중 하나만 contextually 제안.
- 완료 성공 직후 리뷰를 바로 띄우지 않고 두 번째 성공부터 요청.

### Day 3

- Shortcut 사용이 없는 사용자에게 한 번만 Quick Add Shortcut guide.
- Live Activity가 stale이면 `다시 시작` + Widget continuity를 안내.
- 반복 Todo 사용자를 분리 측정.

### Day 7

- 사용 패턴에 맞는 Pro template preview를 제안.
- Todo 중심이면 Image + Todo, Memo 중심이면 Memo + Todo/D-Day를 보여준다.
- StoreKit 7일 trial 종료 전에 사용 중인 Pro 결과와 유지되는 가치를 설명한다.

### Day 30

- Morning Briefing, 반복 Todo, Widget interactive completion이 장기 습관을 만든다.
- 앱을 열지 않아도 `Core Active User`로 집계한다.

### 리텐션 사용자 정의

| 사용자 | 판정 신호 |
|---|---|
| App Open User | 앱 foreground/open |
| Live Activity User | activity update/start/interaction |
| Shortcut User | `shortcut_quick_add` 또는 refresh |
| Widget User | timeline request/open/interaction |
| Todo Completion User | 앱/Live/Widget 완료 |
| Core Active User | 위 다섯 신호 중 핵심 행동 1개 이상/일 |

현재 Firebase는 대부분 원시 신호를 가지고 있다. `core_active_user`는 중복 없이 하루 한 번 App Group에서 claim하는 집계 이벤트로 추가해야 한다.

---

## 13. UI/UX 개선안

### 13.1 iOS 26 적용 원칙

Apple의 최신 지침에 따르면 표준 SwiftUI navigation, bar, sheet, popover, control은 최신 SDK에서 Liquid Glass를 자동 적용한다. 커스텀 배경이 이 효과를 가릴 수 있으므로 먼저 시스템 component를 살리고, custom glass는 핵심 control에 제한한다.

적용:

- `TabView`, `NavigationStack`, `NavigationSplitView`, `toolbar`, `Form`, `sheet`, `Menu`, `Picker` 유지/확대.
- toolbar/tab bar의 커스텀 불투명 background 제거.
- Quick Capture, Live status, primary floating actions만 glass.
- content card는 semantic surface/material.
- 색상은 glass tint보다 콘텐츠 상태/CTA 강조에 사용.
- iOS 16~25 fallback을 유지해 최소 OS를 26으로 올리지 않는다.

적용 금지:

- 모든 section/card에 `glassEffect`
- 텍스트가 긴 Todo/Memo 뒤에 clear glass
- 여러 개 독립 glass container를 무분별하게 생성
- 투명도를 강제해 Reduce Transparency를 무시

### 13.2 Onboarding

현재 5단계:

```text
Intro → First Todo → Preview → Activate → Done
```

잠금화면 표시까지 최소 4번의 CTA/keyboard action, 완료 화면 종료까지 5번이 필요하다.

개선 3단계:

```text
1. 한 줄 입력
2. 실제 잠금화면 preview + Show on Lock Screen
3. 성공 + Widget/Shortcut 중 하나 선택
```

- 첫 화면에서 자동 focus 유지.
- tutorial illustration보다 실제 사용자 문장을 preview에 사용.
- skip은 유지하되 Live Activity 제한을 긴 설명으로 앞세우지 않는다.

### 13.3 Main / Lock Screen

- 상단: `오늘 · Live 상태 · 만료/갱신` 한 줄.
- 중앙: 실제 잠금화면 preview와 현재 template.
- 하단: Todo/Memo Quick Capture glass accessory.
- 상세 설정은 `…` Menu로 보내되 template/Live state는 숨기지 않는다.
- 현재 여러 개의 18pt 카드 border를 줄이고 그룹 간 spacing으로 계층을 만든다.

### 13.4 iPad

Regular width:

```text
Sidebar: Lock Screen / Calendar / Settings
Detail left: live preview
Detail right: today items / quick capture
```

- `NavigationSplitView` 사용.
- portrait/narrow에서는 기존 `TabView`/single stack으로 collapse.
- 720pt 고정 단일 컬럼 제한을 제거하고 readable column width를 영역별로 둔다.
- keyboard shortcut: New Todo, New Memo, Start/Refresh Live.
- pointer hover/focus/drag reorder 지원.

### 13.5 Calendar

- iPhone: 월 grid + 선택 날짜 list 유지.
- iPad: 좌측 월/주 calendar, 우측 selected day editor 2열.
- 상단 month navigation은 표준 toolbar grouping.
- 단순 dot 외에 Todo/Memo 종류를 색이 아닌 symbol/shape로도 구분.

### 13.6 Template

- 이름/아이콘 카드 대신 실제 miniature lock-screen preview를 보여준다.
- Free/Pro badge를 유지하되 잠금 template도 tap 가능 preview로 만든다.
- 선택 시 glass morph는 iOS 26에서만, older OS는 scale/fade.

### 13.7 Add

- 기본: Home inline capture.
- 고급: 기존 Sheet에서 반복/날짜/아이콘.
- Memo/Todo segmented picker를 키보드 바로 위 또는 bottom accessory에 둔다.
- Todo 여러 줄 붙여넣기 시 “3개 Todo로 추가” preview.
- 저장 success haptic과 Live update 상태를 1초 이내 표시.

### 13.8 Settings

- `Form`은 시스템 UI를 그대로 사용해 최신 디자인을 자동 적용.
- Live/Widget/Shortcut을 각각 장황한 설정으로 늘리지 말고 `잠금화면 연결` section으로 묶는다.
- Saved Links는 Advanced 아래로 이동.
- privacy preview를 inline으로 제공.

### 13.9 Paywall

- 상단 40%: 실제 Pro 잠금화면 preview.
- 중단: 3개 outcome benefit만 표시.
- 하단: 연간 기본 상품 + sticky CTA.
- Lifetime은 expand/secondary 위치.
- 닫기/Restore/Terms/Privacy는 즉시 보이고 지연시키지 않는다.

### 13.10 Shortcuts Setup

- 두 App Shortcut을 카드로 설명하지 말고 실제 phrase와 결과를 한 줄씩 제공.
- `Add to LockTodoNote`는 현재 target 설정에 따라 Todo/Memo가 달라져 혼란이 있다. P1에서 `Add Todo`, `Add Memo`, `Get Today Briefing`으로 명시적 action을 추가하되 기존 action은 호환성 때문에 유지한다.

### 13.11 Morning Briefing

- 앱 화면은 Shortcut 설치 버튼, 포함 항목 toggle, preview transcript만 제공.
- 알람 자동화 생성은 사용자가 Shortcuts 앱에서 직접 완료해야 한다.
- 날씨는 앱이 별도 위치 권한을 요구하기보다 Shortcuts 시스템 action으로 가져오는 구성을 우선한다.

### 13.12 Accessibility

- 사용자 지정 배경에서 WCAG 대비에 맞게 전경색 자동 선택.
- Dynamic Type XXXL에서 Todo 줄, paywall product card, calendar overflow 검사.
- VoiceOver 순서: 상태 → preview → quick capture → content.
- 색만으로 selected/done/live를 구분하지 않는다.
- Reduce Transparency에서 opaque material fallback.
- Reduce Motion에서 glass morph/scale을 단순 fade로 대체.
- iPad keyboard focus ring과 Full Keyboard Access 검사.

---

## 14. 개선 기능 평가 및 수정 우선순위

점수는 5점 만점이다. `개발 비용/기술 위험/UI 복잡도`는 **높을수록 부담이 큼**을 뜻한다.

| Priority | 기능 | 사용자 가치 | 잠금화면 핵심 | 리텐션 | 결제 | 개발 비용 | 기술 위험 | UI 복잡도 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| P0 | iOS 26 adaptive shell + control layer | 5 | 4 | 4 | 3 | 3 | 2 | 2 |
| P0 | 한 화면 Quick Capture + 줄 분리 | 5 | 5 | 5 | 3 | 3 | 2 | 2 |
| P0 | Live 수명/재시작/상태 UX | 5 | 5 | 5 | 3 | 2 | 2 | 1 |
| P0 | Home medium Widget fallback + 완료 | 5 | 5 | 5 | 3 | 4 | 3 | 2 |
| P0 | 실제 결과 Pro Preview + Paywall | 4 | 4 | 3 | 5 | 3 | 2 | 2 |
| P1 | Todo 편집/정렬/아이콘/시간 | 4 | 4 | 4 | 2 | 3 | 2 | 3 |
| P1 | Morning Briefing App Intent/가이드 | 4 | 4 | 5 | 4 | 4 | 3 | 2 |
| P1 | 명시적 Add Todo/Add Memo Shortcut | 4 | 5 | 4 | 3 | 3 | 2 | 1 |
| P1 | Apple Reminders 단방향 연동 | 4 | 3 | 4 | 3 | 4 | 4 | 3 |
| P2 | iCloud/CloudKit sync | 4 | 2 | 4 | 3 | 5 | 5 | 2 |
| P2 | 주간 일정 view | 3 | 2 | 3 | 2 | 4 | 3 | 3 |
| P3 | Wallpaper export | 2 | 1 | 2 | 2 | 3 | 3 | 3 |
| Do Not Build | 스티커 canvas/editor | 2 | 1 | 2 | 2 | 5 | 3 | 5 |
| Do Not Build | 광고 SDK 무료 모델 | 1 | 1 | 1 | 2 | 3 | 4 | 3 |
| Do Not Build | 모든 콘텐츠에 glass | 1 | 1 | 1 | 1 | 2 | 3 | 5 |

### 관련 파일

| Priority | 기능 | 관련 파일 |
|---|---|---|
| P0 | iOS 26 shell/iPad | `App/RootView.swift`, `Core/Theme/AppPalette.swift`, 각 Feature View |
| P0 | Quick Capture | `Features/Todo/QuickAddSheet.swift`, `Features/Home/LockScreenTabView.swift`, `Core/Storage/CardStore.swift` |
| P0 | Live lifecycle | `Core/LiveActivity/LiveActivityService.swift`, `Features/Home/LockScreenTabView.swift`, `GlanceCardAppIntents.swift` |
| P0 | Widget fallback | `GlanceCardLockScreenWidget.swift`, `GlanceCardWidgetBundle.swift`, App Group snapshot |
| P0 | Pro Preview | `PaywallView.swift`, `TemplatePickerView.swift`, `AppEnvironment.swift`, Analytics |
| P1 | Todo editing | `LockScreenTabView.swift`, `CalendarTabView.swift`, `CardStore.swift`, `CardMutations.swift` |
| P1 | Morning Briefing | `GlanceCardAppIntents.swift`, Settings, Dashboard shared models |
| P1 | Reminders | 신규 EventKit service, Settings, Card mapping |

---

## 15. Phase별 수정 계획

### Phase 1 — P0 핵심 UX

1. iOS 26 visual audit와 compatibility fallback 공통 modifier 설계.
2. iPhone TabView는 유지하고 iPad `NavigationSplitView` 적용.
3. Home inline Quick Capture, Memo/Todo picker, 여러 줄 Todo 분리.
4. Live status/stale/refresh/fallback 상태를 한 lifecycle component로 통합.
5. Home medium Widget + iOS 17 interactive Todo 완료.
6. 실제 사용자 데이터 기반 Pro preview와 구매 후 즉시 적용.

Exit criteria:

- 첫 Todo에서 잠금화면 활성화까지 3단계 이하.
- iPad portrait/landscape에서 의미 있는 2열 사용.
- iOS 26/18/17/16 fallback 외형과 기능 QA.
- Reduce Transparency/Motion, Dynamic Type QA.

### Phase 2 — Retention

- Add Todo/Add Memo Shortcut 분리.
- Todo 편집/정렬/시간/아이콘 최소 UI.
- Live Activity stale 재시작 안내와 Widget continuity.
- Core Active User 집계.
- 리뷰 요청을 두 번째 완료 또는 3일 내 두 번째 성공으로 조정.

### Phase 3 — Monetization

- paywall preview/trigger A/B.
- 연간 trial CTA 전면화.
- Lifetime 가격/노출 실험.
- purchase 후 template 적용 success funnel.
- Pro template별 conversion 분석.

### Phase 4 — Differentiation

- `Get Today Briefing` App Intent.
- 알람 종료 Personal Automation 설치 가이드.
- Apple Reminders 단방향 연동 실험.
- sync는 retention 데이터가 뒷받침될 때 별도 설계.

### Phase 5 — Polish

- 접근성, contrast, haptic, motion.
- iPad keyboard/pointer.
- Widget/Live Activity performance.
- App Store 스크린샷과 onboarding 문구 통일.
- 오래된 `docs/migration-progress.md`를 실제 코드 상태와 동기화.

---

## 16. 삭제/단순화 계획

1. Home의 중복 카드 border와 surface를 줄이고 section hierarchy로 대체.
2. Lock Screen 탭 상단 `+` Menu와 각 section의 Add 버튼을 Quick Capture 하나로 통합.
3. first success 직후 자동 full paywall은 soft teaser A/B 후보로 낮춘다.
4. Saved Links를 Settings의 Advanced 영역으로 이동하고 onboarding/paywall에서 제외.
5. Settings의 template/show todo/show memo 중복 진입을 `잠금화면 구성` destination 하나로 묶는다.
6. 24시간 template preview와 7일 subscription trial의 메시지를 분리해 혼란을 제거.
7. 현재 문서의 Firebase/언어/링크 미구현 등 오래된 상태 설명을 갱신한다.

---

## 17. 성공 측정 지표

### 17.1 Activation

- `onboarding_start`
- `onboarding_step_view`
- `first_todo_created`
- `lockscreen_preview_seen`
- `live_activity_start_success/failed`
- `activation_complete`

목표:

- onboarding start → activation complete +20%
- first Todo → Live Activity success 70% 이상
- median first value time 90초 이하

### 17.2 Capture/Completion

- `todo_created(source: inline|sheet|shortcut|widget)`
- 신규 `memo_created`
- 신규 `multiline_todo_imported(count)`
- `todo_completed(source: app|live_activity|widget)`
- `shortcut_quick_add`

목표:

- inline capture 사용자의 당일 두 번째 capture +15%
- Live/Widget 완료 비중 30% 이상

### 17.3 Live/Widget continuity

- `live_activity_start_success`
- `lockscreen_activity_ended`
- 신규 `live_activity_became_stale`
- 신규 `live_activity_restarted`
- `widget_timeline_requested`
- 신규 `widget_installed_confirmed`
- 신규 `widget_todo_completed`

목표:

- stale 사용자 24시간 내 restart 또는 Widget active 60% 이상
- activated 사용자 중 Widget 설치 25% 이상

### 17.4 Monetization

- `pro_template_tapped`
- `pro_info_sheet_viewed`
- 신규 `pro_preview_viewed/interacted`
- `paywall_seen`
- 신규 `plan_selected`
- `purchase_started/completed/cancelled/failed`

목표:

- paywall → purchase started +30%
- purchase started → completed 60% 이상
- Pro preview → paywall 35% 이상
- 가격 변경 전후 cohort 분리

### 17.5 Retention

- 신규 `core_active_user(activity_type)` 하루 1회
- D1/D3/D7/D30을 app-open retention과 core-active retention으로 분리
- Shortcut/Widget/Live-only 사용자를 누락하지 않는다.

---

## 18. 최종 결론

### Live Note에서 반드시 가져와야 할 것 3개

1. 메인 화면 직접 입력과 여러 줄 Todo 자동 분리.
2. Live 상태를 항상 보여주고 Shortcut/Widget/Calendar로 이어지는 lifecycle.
3. 핵심 무료·광고 없음으로 신뢰를 만든 뒤 시각 개인화/확장에 과금하는 구조.

### Live Memo에서 반드시 가져와야 할 것 3개

1. iOS 26의 플로팅 navigation/control layer와 콘텐츠 카드 분리.
2. Wallpaper/Live/Widget처럼 전달 방식을 같은 레벨에서 설명하는 continuity 개념.
3. 앱 preview와 실제 잠금화면 결과의 높은 시각적 일치.

### 두 앱에서 절대 가져오지 말아야 할 것 3개

1. 광고 배너와 추적 중심 무료 모델.
2. 스티커/링크/일정 기능을 모두 핵심 화면에 쌓는 범위 확장.
3. 콘텐츠 전체에 glass/투명도를 남용하는 디자인.

### LockTodoNote가 두 앱보다 확실히 나아질 차별화 3개

1. Todo 완료 + 날짜 선택 + Memo/Todo 전환이 가능한 Interactive Live Activity.
2. Live Activity 종료 후 Home Widget로 자연스럽게 이어지는 continuity.
3. 알람 종료 후 날씨·Todo·Memo·D-Day를 읽는 Morning Briefing.

### 다음 업데이트에서 실제로 구현할 P0 — 최대 5개

1. iOS 26 Liquid Glass control layer + iPad adaptive `NavigationSplitView`.
2. Home 한 화면 Quick Capture + 여러 줄 Todo 분리.
3. Live Activity 활성/만료/재시작/Widget fallback UX.
4. Home Screen medium interactive Widget fallback.
5. 실제 사용자 데이터가 들어간 Pro Preview + 결과 중심 Paywall.

구현 순서는 위 P0를 기준으로 하되, 사용자가 `START IMPROVEMENT`라고 승인하기 전에는 코드 변경을 시작하지 않는다.

---

## Sources

- [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple — NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Apple — tabViewBottomAccessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:))
- [Live Note App Store](https://apps.apple.com/kr/app/id6756247075)
- [Live Note 공식 사이트](https://lvnt.my/)
- [Live Memo App Store](https://apps.apple.com/kr/app/id6502684453)
- [LockTodoNote App Store](https://apps.apple.com/kr/app/id6783183501)

