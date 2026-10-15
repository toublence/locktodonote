# 설정 오류 수정 및 직접 재검증 — 2026-10-08

## 결과

기존 직접 테스트에서 발견한 새로고침 단축어 실패, 단축어 이름의 번역 키 노출, 위젯 설치 안내의 영어 표시를 수정했다. 현재 소스로 정상 서명 Debug 빌드 1회 성공 후 기존 QA 시뮬레이터에 재설치해 직접 확인했다.

## 변경

- Quick Add와 새로고침 단축어를 `LiveActivityIntent`로 변경하고 인텐트 구현 및 지역화 도우미를 호스트 앱 타깃에도 포함. 앱 프로세스에서 실행하여 Live Activity 시작·갱신을 처리하도록 구성.
- 새로고침 시 새 활동 생성 성공 후 기존 활동 종료. 요청 실패 시 기존 활동 보존.
- 새로고침 성공 시 시작 시각·시작/명시적 중지 플래그·만료 분석 플래그 갱신.
- 누락된 단축어 이름·추가 대상·실패 안내 및 위젯 설치 안내를 지원하는 10개 언어로 추가.
- 앱에서도 인텐트가 사용하는 기존 지역화 문구를 읽을 수 있도록 누락 항목 추가. 기존 번역 항목은 유지.
- 앱 번들 ID, URL scheme, App Group, 기존 데이터 파일 및 무료 사용량 키는 유지.

## 직접 확인

- 시뮬레이터: `LockTodoNote Settings QA`, iPhone 17 Pro Max / iOS 26.1.
- 단축어 앱에 `LockTodoNote에 추가`, `잠금화면 새로고침`으로 표시. 이전 번역 키 노출 해소.
- 실제 새로고침 단축어 실행 후 `잠금화면을 새로고침했어요` 성공 메시지 표시.
- 앱으로 복귀하여 Live Activity 활성, 약 7시간 59분 남음, 할 일 3개·메모 2개 확인.
- 위젯 설치 상태가 `위젯이 설치됐어요`로 표시.
- 위젯 확인 버튼 실행 후 `위젯 설치를 확인했어요.` 메시지 표시.
- 기존 할 일 3개·메모 2개와 단축어 사용량 `5 / 5회` 보존.
- 빌드 결과: `BUILD SUCCEEDED`. 로그: `/tmp/locktodonote-settings-fix-build.log`.

## 범위 및 미검증

실제 기기/Siri/액션 버튼 및 8시간 만료는 재검증하지 않았다. 이번 수정 후 Quick Add의 추가 성공 경로는 기존 사용량 5회에 도달한 상태라 재실행하지 않았다. 최초 테스트의 추가 성공·무료 제한 확인은 이전 기록에 있으며, 이번에는 실행 프로토콜과 호스트 앱 포함을 변경했다. 새로고침 실패 시 기존 활동을 보존하는 예외 경로는 코드로 개선했으며 강제 실패를 유도하지 않았다. 동기화 및 데이터 화면의 기기 간 동기화와 요약형 아침 브리핑 생성은 기존에 구현되지 않은 기능이며 이번 오류 수정에서 추가하지 않았다.

## 수정 파일

- `Extensions/WidgetExtension/GlanceCardAppIntents.swift`
- `Extensions/WidgetExtension/Localizable.xcstrings`
- `LockTodoNote/Resources/Localizable.xcstrings`
- `project.yml` (XcodeGen으로 프로젝트 갱신)

## 근거

Apple ActivityKit 문서는 인텐트에서 Live Activity를 시작할 때 LiveActivityIntent 채택을 요구하며, WidgetKit 문서는 해당 인텐트를 앱 타깃에 포함하도록 안내한다.

- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
