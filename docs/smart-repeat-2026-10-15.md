# Smart Repeat 구현 — 2026-10-15

## 제공 범위

- 무료: 기존 매일·평일·매주 반복 유지.
- Pro: 요일 조합(예: 월·수·금), 매월 마지막 요일(예: 마지막 금요일), 격주 지정 요일(예: 화요일), 2~365일 간격.
- 오늘·캘린더 빠른 입력, 추가 시트, 할 일 편집에서 `Smart Repeat · Pro`로 설정한다. 요일 조합은 최소 1개를 선택해야 저장된다.
- 첫 유효 날짜를 안내하고 새 할 일을 그 날짜에 등록한다. 격주는 시작일 이후 첫 지정 요일을 기준으로 14일마다 반복하며, N일 간격은 첫 등록일을 기준으로 계산한다.
- 일수 계산은 초 단위가 아닌 Calendar 날짜 차이를 사용한다. 월말·윤년·연말과 일광절약시간을 고려한다.

## 저장 및 실제 동작

`AdvancedRepeatRule.swift`에 별도 규칙을 정의하고 `ChecklistItem.advancedRepeat`에 저장한다. 기존 JSON에 필드가 없어도 기존 무료 반복으로 디코딩한다.

실제 다음 할 일 생성과 잠금화면 내일 미리보기는 `ChecklistItem.isRecurrenceDue`를 공유한다. 기존 완료 처리, 미완료 이월, 시리즈 중복 방지를 유지한다. 시리즈 규칙을 편집하거나 해제하면 같은 시리즈의 저장된 반복 메타데이터도 갱신해 이전 규칙이 다시 활성화되지 않게 한다. 완료 상태와 완료 기록은 보존한다.

기존 아키텍처와 동일하게 저장된 카드의 생성은 앱/단축어의 공유 데이터 갱신 시 수행되며, 잠금화면은 내일 미리보기를 미리 구성한다. 모든 미래 날짜에 카드를 미리 생성하거나 OS 알림을 추가하는 기능은 아니다.

## Pro 정책과 연결

- UI와 CardStore 저장 경로 양쪽에서 고급 규칙의 신규 생성·변경을 Pro로 제한한다. 기존의 템플릿용 임시 체험은 이 기능을 해제하지 않는다.
- 무료 사용자는 설정을 살펴본 뒤 전용 `smart_repeat` 결제 화면을 열 수 있다. 구매 후 돌아와 설정을 저장한다.
- 구독 만료 후에도 기존에 설정한 반복과 완료 기능을 유지한다. 고급 규칙의 신규 설정·변경에는 다시 Pro가 필요하며, 고급 반복 해제 및 무료 반복으로의 전환은 가능하다.
- 이번 기능은 설정 화면으로 반복 조건을 지정하는 기능이다. Smart Quick Add의 문장 인식 및 Shortcut 입력 문법은 기존 지원 범위를 유지한다.

## 변경 위치

- 공유 모델: `AdvancedRepeatRule.swift`, `ChecklistItem.swift`
- 공유 생성·미리보기: `CardMutations.swift`, `DashboardComposer.swift`
- 저장·구독: `CardStore.swift`, `AppEnvironment.swift`
- 입력·수정: `AdvancedRepeatPicker.swift`, `QuickAddSheet.swift`, `QuickCaptureView.swift`, `LockScreenTabView.swift`
- 결제 안내: `PaywallView.swift`
- 테스트: `AdvancedRepeatTests.swift`

## 검증 결과와 제한

요청한 저비용 검증 1회 안에서 수정된 앱 Swift 파일 구문 검사와 관련 공유 패키지 테스트를 실행했다. 전체 앱 빌드 및 기기 UI 검증은 수행하지 않았다.

- 앱 파일 구문 검사 및 공유 모듈 컴파일 성공.
- 신규 고급 반복 테스트 9개 중 8개 통과: 요일 조합, 월말/윤년, 격주 연말 경계, 3일 간격, 잘못된 규칙 거부, 저장 호환성, 중복 방지, 내일 미리보기.
- DST 테스트는 테스트 도우미가 기기의 현재 시간대로 날짜를 해석한 뒤 미국 시간대로 변환해 날짜가 하루 전으로 바뀌는 문제로 실패했다. 테스트 도우미를 주입한 Calendar로 직접 날짜를 생성하도록 수정했다. 규칙 구현은 변경하지 않았다. 검증 횟수 제한에 따라 수정 후 재실행하지 않았다.
- Smart Quick Add 기존 테스트 14개 통과. Dashboard composition 테스트도 통과.
- 함께 실행된 범위에서 `quickCaptureServiceParsesBulletsAndCleansMemo` 1개(메모 줄 끝 공백 기대값), `mixedTemplatesFollowTheSelectedInputTab` 1개(2개 인자의 Shortcut 대상 기대값)도 실패했다. 이 두 동작은 이번 기능의 변경 대상이 아니므로 수정하지 않았다.
- 실행 전체: 69개 테스트 중 3개 실패, 총 4개 실패 기록. 전체 검증이 통과했다고 볼 수 없으며, 재검증 시 DST 수정 결과 및 위 별도 실패를 확인해야 한다.
