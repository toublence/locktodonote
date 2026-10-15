# 단축어 직접 테스트

> 후속 수정: 새로고침 단축어 성공 및 두 단축어 이름의 한국어 표시를 확인했다. 아래 문제 목록은 수정 전 기록이다. [수정 기록](../settings-fix-report-2026-10-08.md) 참조.

- 환경: 별도 iPhone 17 Pro Max / iOS 26.1 시뮬레이터의 실제 단축어 앱.
- 판정: Quick Add·기본 대상·무료 한도 정상. 새로고침 단축어와 이름 표시 문제 확인.

## 정상 동작

- 설정의 단축어 앱 열기 버튼으로 시스템 단축어 앱 실행.
- 기본 추가 대상을 메모로 변경한 뒤 Quick Add 실행. `QA shortcut memo`와 `QA quota 2` 추가 성공 메시지 확인.
- 실제 홈 위젯에 메모 표시. 앱 재실행 후 두 메모 유지.
- 기본 추가 대상을 할 일로 변경한 뒤 Quick Add 실행. `QA shortcut todo 3`, `QA shortcut todo 4`, `QA shortcut todo 5` 추가 성공 메시지 확인.
- 실제 홈 위젯 및 앱에 세 할 일 표시, 앱 재실행 후 유지.
- 총 5회 성공한 뒤 6번째 Quick Add 실행은 무료 추가 횟수를 모두 사용했다는 안내로 차단. 텍스트 입력 요청 단계 전 차단.
- 앱에 오늘 사용량 `5 / 5회` 표시. 앱 복귀 시 Pro 사용 안내가 표시되고 나중에로 닫을 수 있음.

## 확인한 문제

1. 단축어 앱의 두 자동 제공 단축어 이름에 `shortcuts.add.shortTitle`, `shortcuts.refresh.shortTitle` 번역 키가 그대로 표시됨. 사용자가 정상 이름으로 알아보기 어려움.
2. Live Activity 활성 상태에서 새로고침 단축어를 1회 직접 실행했을 때 `The Lock Screen could not be refreshed. Open the app and try again.` 실패 메시지 반환. 이후 앱에서 기존 Live Activity 활성 상태는 유지됨. 원인은 확정하지 않음.
3. Quick Add를 실행하는 동안 Dynamic Island가 바로 갱신되는지는 확인하지 못함. 앱 복귀 후 개수는 반영됨.

- 미검증: 실제 Siri 음성 명령/액션 버튼, 직접 지정한 날짜·대상 파라미터, 자정 초기화, 실제 Pro 무제한 사용, 앱 프로세스 종료 상태의 Quick Add, 긴 텍스트/여러 줄 입력.
