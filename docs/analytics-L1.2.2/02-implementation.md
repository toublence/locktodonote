# Firebase 계측 구현 보고서

2026-10-31 · 출시 후보 `1.2.2 (22)` · 배포하지 않음

## 구현

- 기존 자체 이벤트 이름을 유지했다. `AnalyticsService.log` 한 경로에서 `analytics_release=L1.2.2`, 정확한 `app_version`, 실제 `app_build`, 기존 `analytics_schema_version=2`를 부여한다. 기존 app_version의 ‘버전 (빌드)’ 혼합을 수정했다. Firebase first_open/session_start/화면/자동 구매 이벤트를 수동 복제하지 않는다.
- `telemetry_environment`는 debug/sandbox/release_unknown이다. receipt가 없다고 Production을 단정하지 않는다. 거래 환경은 검증된 StoreKit Transaction의 environment로 별도 기록한다. unknown은 실제 결제로 계산하지 않는다.
- Firebase의 이벤트당 25개 속성 한도를 적용했다. 필수 릴리스 식별·발생/전송 시각·큐 ID를 우선 보존하고 중복 가격/개수/화면/기기 별칭부터 제외한다. 기존 이벤트의 모든 선택적 파라미터가 항상 존재한다고 가정하면 안 된다. 이름과 핵심 의미는 유지한다.
- source/entry_source/surface/action_origin은 허용 enum으로 제한했다. 외부 단축어가 임의로 넣은 source와 이관의 원본 오류 문자열을 그대로 보내지 않는다. 내용·사진·경로·미리알림 원본 ID·규칙 이름·사용자 정의 목록 이름을 추가하지 않았다. 이벤트 연결용 UUID는 사람/할 일 식별자가 아니다.
- 작성 시작/결과는 source별 세션으로 묶고, 소요 시간은 under_10s/10_29s/30_119s/120s_plus다. 앱이 종료되거나 UI 이탈이 관측되지 않은 세션은 다음 시작을 취소로 만들어 채우지 않는다. 실제 원인은 unknown이다.
- 카드 저장 성공 후 수정·삭제·완료 취소·반복 여부·미리알림 완료 맥락을 기록한다. 기존 대표 생성·완료 이벤트와 보조 맥락 이벤트를 합산하지 않는다.
- 오늘 메모 저장에서 기록용/표시용·기존 메모 교체 여부·설정 불변·개별 규칙 제한을 측정한다. 저장 뒤 템플릿 변경은 기존 템플릿 이벤트의 발생 시각과 연결해 관찰하며 인과관계로 해석하지 않는다.
- 표시 후보 구간·기존 규칙의 전체/개별 선택·새 항목의 범위 포함·규칙 저장·자동 전환 활성화·빈 구성 저장 바로가기를 기록한다. 후보는 코드상 계산이고 실제 시청이 아니다. UI 기능이나 순서를 추가하지 않았다.
- 구매 결과 이름과 상품·가격·권리는 그대로다. `l122_purchase_application`은 실제 후속 적용의 success/failed/display_recovery_needed/not_requested를 분리한다. 미리보기 목적이 없으면 기능 적용 성공을 만들어내지 않는다. 비템플릿 기능은 이후 feature 성공과 시간 순서로 평가하며 거래별 완벽한 연결로 주장하지 않는다.

## 확장 큐

App Group 이벤트에는 origin_app_version/origin_app_build/origin_release/origin_environment를 발생 당시 추가한다. 앱은 occurred_at_ms와 forwarded_at_ms를 분리해 전송한다. 전달받은 옛 이벤트에 원본 버전이 없으면 unknown_legacy다. 현재 전송 앱의 릴리스로 원본 행동 버전을 소급 분류하지 않는다.

기존 큐 상한은 100개다. 위젯 timeline 및 activity_updated는 각각 최대 시간당 1회로 제한해 기술 로그가 직접 행동을 밀어내는 위험을 줄였다. 상한 폐기 누적 증가분은 l122_queue_health로 보고한다. 한 시간 내 기술 콜백 횟수를 원본 수로 복원할 수는 없다.

pending 완료/단축어 추가와 카드 파일 commit을 분리했다. 새 단축어 큐에는 선택적인 분석용 UUID/source만 추가해 과거 큐와 호환한다. 내용 ID를 서버에 보내지 않는다. 기존 저장·반복·이월 계산은 재작성하지 않았다. commit은 해당 원본 UUID로 연결하며 결과 unresolved를 성공으로 세지 않는다.

Firebase logEvent는 서버 수신 확인을 반환하지 않는다. 큐 acknowledge는 SDK 호출에 넘겼다는 뜻이며 서버 ACK가 아니다. 호출 직후 프로세스가 중단되면 재전송될 수 있어 BigQuery에서 사용자·이벤트 이름·event_id로 중복 제거한다. 같은 event_id의 todo_completed와 external_commit은 서로 다른 단계라 둘 다 보존한다.

## 기존 설정과 미확인 사항

동일 Firebase 프로젝트 `q-lens-3c1fd`에서 실제 번들 `com.namslab.glancecard`를 등록하고 콘솔에서 받은 공식 GoogleService-Info.plist를 적용했다. 기존 `fit.ttak.app` 등록과 과거 자료는 유지한다. GA 속성 528972146에서 실제 번들 스트림 15362500826과 Firebase App ID의 일치를 확인했다. 기존 등록에서도 지연 후 이벤트가 도착했으므로 번들 불일치를 지연의 유일한 원인으로 단정하지 않는다.

실제 iPad DebugView의 widget_configuration_checked에서 analytics_release=L1.2.2, app_version=1.2.2, app_build=22, analytics_schema_version=2를 확인했다. 전체 이벤트의 수신·정확히 한 번 전송을 모두 입증한 것은 아니다. DEBUG의 -device-qa는 기존대로 수집을 끄며, 이번 실기기 확인에는 사용하지 않았다.

Firebase 앱/스트림 변경 시 SDK first_open이 재발생할 가능성을 고려했다. l122_release_observed는 로컬 기존 설치 기록으로 new_observed/existing_or_unknown을 구분해 릴리스당 1회 기록한다. SQL 신규 코호트는 SDK first_open과 new_observed를 함께 요구한다. 기존 고객을 새 설치로 소급 분류하거나 과거 익명 ID 연속성을 보장하지 않는다.

구매 화면의 체험 가능 안내는 trial_basis=quoted_context다. purchase_completed는 검증 Transaction의 환경과 실제 offer/paymentMode를 이용해 transaction_trial_state=free_trial/not_trial/unknown을 기록한다. iOS 17.2 미만 등 증거가 없으면 unknown이며 is_trial을 생략한다. 이전 시도의 거래 환경은 새 시도에 넘기지 않는다. 표시 가격은 실제 매출이 아니다. 상품·가격·권리 판단 코드는 변경하지 않았다.

## 참고 문서

[Firebase Analytics API·파라미터 한도](https://firebase.google.com/docs/reference/swift/firebaseanalytics/api/reference/Classes/Analytics), [DebugView 확인 방법](https://firebase.google.com/docs/analytics/debugview), [BigQuery 스키마](https://support.google.com/analytics/answer/7029846?hl=en). SDK 및 서버의 관측 제한은 아래 분석 계약에 반영했다.

## 최종 점검에서 추가 발견한 범위

캘린더 QuickCaptureView에는 화면 표시/유형 변경이 selectedContentSection을 저장하고, 메모를 항상 표시 선택으로 저장하는 연결이 남아 있었다. 오늘/빠른 작성에 적용했던 승인 P0 계약과 같도록 캘린더에서도 입력 유형만 바꾸고, 새 메모의 표시 기본값은 기존 표시 문맥·개별 규칙을 따르게 했다. 새 컨트롤/화면 배치는 추가하지 않았다. 실제 캘린더 메모 저장 후 오늘의 할 일 표시 유지와 기록 전용 메모 저장을 확인했다.

외부 병합의 읽기/쓰기 실패는 고정 코드 merge_read_or_write_failed로 card_save_failed를 기록하고 큐를 성공 처리하지 않는다. 원본 오류 문자열은 보내지 않는다. 작성 실패 결과는 create_todo/create_memo에만 연결해, 관련 없는 편집/병합 오류가 진행 중 작성 세션을 실패로 닫지 않게 했다.
