# Smart Quick Add 문장 자동 인식

작성일 2026년 10월 15일

Today 입력, 캘린더 빠른 입력, 할 일 추가 시트, 기존 Add to LockTodoNote Shortcut에서 같은 문장 인식기를 사용한다. 외부 AI나 네트워크 요청 없이 기기에서 처리한다.

## 입력 예시

| 입력 | 등록 결과 |
| --- | --- |
| 내일 오후 3시 병원 예약 | 내일 15시의 병원 예약 |
| 매주 월요일 운동 | 다음 도래하는 월요일부터 매주 반복 |
| 매주 평일 오전 9시 출근 | 평일 반복과 오전 9시 |
| 모레 장보기 | 모레의 장보기 |
| 3일 후 서류 제출 | 입력일부터 3일 뒤 |
| 2026-10-20 서류 제출 | 2026년 10월 20일 |
| 10월 20일 서류 제출 | 다음 도래하는 10월 20일 |
| tomorrow 3pm appointment | 내일 15시의 appointment |
| every Monday exercise | 매주 월요일 반복 |

오늘·내일·모레, N일 후, 한국어 및 ISO 날짜, 요일, 오전·오후·24시간 시각, 매일·평일·매주 단일 요일을 지원한다. 여러 줄은 각 줄의 날짜를 따로 해석한다. 한국어 날짜와 시간은 예시처럼 단어를 구분해 입력한다.

## 확인과 우선순위

앱에서는 저장 전에 정리된 제목과 날짜·시간·반복을 미리 보여준다. 인식한 반복은 기존 반복 선택기에 반영하며 사용자가 바꾼 값이 우선한다. 문장 자동 인식을 끄면 문장을 그대로 저장한다.

Shortcut의 기존 Date 매개변수를 명시했다면 그 날짜가 문장 날짜보다 우선하고, 문장의 시간은 해당 날짜에 적용한다. 새 Smart date recognition 매개변수는 기본값이 켜짐이며 필요하면 끌 수 있다. 메모 입력과 기존 무료 Shortcut 한도는 유지한다.

날짜 없이 시각만 입력했고 이미 지난 시각이면 다음 도래하는 시각으로 잡는다. 반면 오늘을 명시하면 과거 시각이어도 오늘로 유지한다. 기기의 현재 시간대와 달력을 사용한다.

지원하지 않는 매월 반복, 여러 요일 조합, 잘못된 날짜·시각, 충돌하는 여러 일정은 억지로 일부만 적용하지 않고 원문을 보존한다. 밤 12시처럼 날짜 경계가 모호한 표현도 보존한다. 모든 자연어 문장을 해석하는 범용 인식기는 아니다.

## 저장과 표시

인식된 시각은 할 일의 dueDate와 hasDueTime에 저장하고 앱 목록 및 잠금화면에서 표시한다. 개별 시각에 대한 알림 예약 기능을 추가한 것은 아니다.

Shortcut은 인식 결과를 입력 시점에 확정해 공유 큐에 저장한다. 다음 날 앱을 열어도 내일을 다시 해석하지 않는다. 날짜가 다른 항목을 한 번에 입력해도 각 날짜로 병합한다. 이전 버전의 큐는 원래 방식대로 처리한다.

반복 항목은 원래 기준일을 보존한다. 월요일 항목을 화요일로 이월한 뒤 완료해도 다음 주의 반복 요일은 월요일이다. 다음 반복 항목의 시각도 보존한다. 기존 할 일 파일에 새 필드가 없어도 정상적으로 읽는다.

## 구현 파일과 확인 범위

- [공통 문장 인식기와 저장 결과](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Models/SmartQuickAddParser.swift)
- [앱 입력 미리보기](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Todo/SmartQuickAddPreview.swift)
- [Shortcut과 잠금화면 연결](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift)
- [문장과 저장 호환성 테스트](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Tests/LockTodoNoteSharedTests/SmartQuickAddParserTests.swift)

수정한 앱·Shortcut 파일의 구문 검사와 공통 패키지의 Smart Quick Add 테스트 14개가 통과했다. 이후 모호한 한국어 시간대 표현을 보존하는 제한을 추가했으며 추가 검사는 실행하지 않았다. XcodeGen으로 새 화면 파일을 프로젝트에 반영했다. 전체 앱 빌드와 실기기 Shortcut 실행은 수행하지 않았다.
