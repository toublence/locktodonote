# 신규·재방문·Pro·수익 대시보드

2026-10-31 Firebase·GA·ASC에 접근해 설정을 확인했다. GA 맞춤 측정기준 30개를 실제 등록했다. 아래 패널은 설계이며 완성된 보고서 설치나 BigQuery 실행·실수익 검증을 의미하지 않는다.

## 콘솔 등록

GA 속성 528972146의 기존 맞춤 정의가 비어 있음을 확인한 뒤 다음 이벤트 범위 30개를 등록했다.

`analytics_release`, `app_build`, `source`, `result`, `feature`, `type`, `action`, `template_id`, `selection_mode`, `duration_bucket`, `storage_stage`, `paywall_trigger`, `transaction_environment`, `transaction_trial_state`, `trial_basis`, `cohort`, `measurement`, `candidate_bucket`, `capacity_bucket`, `origin_release`, `is_premium`, `trial_type`, `selected_for_display`, `display_settings_unchanged`, `rule_restricted`, `replaced_existing`, `overflow`, `included_bucket`, `recurring`, `reminder_linked`.

app_version은 기본 앱 버전 측정기준을 사용한다. 새 정의가 일반 보고서에 나타나기까지 24~48시간이 걸릴 수 있으며 과거 자료의 소급 생성으로 취급하지 않는다. [등록 화면](evidence/custom-dimensions-30-2026-10-31.png).

`event_id`, `capture_id`, `request_id`, `attempt_id`, occurred/forwarded/action timestamp, 개별 콘텐츠 ID는 차원으로 등록하지 않는다. UUID/시각은 BigQuery 원본으로 처리한다. count/time 수치도 과도하게 차원을 늘리지 말고 기존 구간을 사용한다. BigQuery 연결은 Firebase 프로젝트의 통합에서 실제 export 활성 여부·데이터셋·보존/비용을 확인한 뒤 진행한다. 문서의 SQL은 권한 있는 콘솔에서 데이터셋과 날짜 파라미터를 채워야 하며 여기서 실행하지 않았다.

## 패널

| 패널 | 분모·분자·분석 |
| --- | --- |
| 신규 | SDK 자동 first_open과 l122_release_observed(cohort=new_observed)가 일치하는 신규 코호트. 온보딩 단계 → 첫 저장 → 표시 요청/성공 → 실제 첫 완료. 모두 같은 사용자·시간 순서/관측 창을 사용 |
| 첫 가치 시간 | 기존 activation은 등록 도달, l122_first_value는 콘텐츠+설정까지 경과. 첫 실제 완료까지는 별도. 실제 시청은 관측 불가 |
| 작성 | capture_id별 started → saved/cancelled/failed/interrupted/type_changed, 시간 구간·표면·유형별 비교. 결과 없음은 crash/포기/미전송을 구별할 수 없음 |
| 기록/표시 | 오늘 메모의 기록용·교체·규칙 제한·설정 불변 비율. 이후 템플릿 변경을 5분 등 명시된 창에서 관찰하고 원인을 단정하지 않음 |
| 핵심 사용 | SDK DAU/WAU와 별도로 원본 행동일 기준 핵심 처리 사용자/일·주, 앱/앱 밖 완료, 최종 저장 확인률, 주간 의미 있는 사용 일수 |
| 리텐션 | 위 조건을 충족한 first_open 설치일 코호트의 정확한 D1/D3/D7/D14/D30. 각 N일이 끝난 성숙 코호트만 분모. 단순 app_returned 수를 리텐션으로 사용 금지 |
| 누적/선택 | 후보 구간·코드 행 상한·초과 상태·전체/개별 선택·새 항목 포함과 이후 선택 변경. 자동 상태 이벤트 수를 사용 빈도로 환산 금지 |
| 지속 기능 | 반복 생성/완료, 미리알림 연결 성공/원본 연계 완료, 자동 전환 저장/활성화 뒤 핵심 사용일. 화면 진입만으로 기능 재사용으로 세지 않음 |
| Pro | feature/trigger별 preview 조작 → paywall_seen → 기본/수동 상품 선택 → 구매 시도 → verified/pending/cancel/fail → 목적 적용/복구. 사용자/시도·시간 순서·기능·코호트별 집계 |
| 광고 | 현 정책상 요청/노출 0이 예상된다. 실제 ad_paid_revenue 콜백이 있다면 테스트 제외 후 AdMob 원장과 대조. 빈 로그를 SDK 장애로 단정하지 않음 |

무료/Pro는 행동 당시 is_premium, 체험은 trial_type·is_trial 및 검증 거래 환경으로 구분한다. 나중 전송된 큐는 원본 is_premium이 우선이며 당시 값이 없으면 unknown이다. debug/sandbox 및 명시 테스트 집단을 제외하고 release_unknown을 자동 Production으로 승격하지 않는다. first_open에는 자체 공통 속성이 없으므로 SDK app_info.version과 해당 코호트의 후속 환경을 함께 본다.

## 사업 수익

30일 평균 일수익 = 같은 확정된 30일의 `(ASC proceeds USD + AdMob 실제 수익 USD) / 30`이다. 누락된 날을 분모에서 빼지 않는다. 결산 확정/추정, 환불·수수료·세금·환율·타임존을 표기하고 단일 통화로 맞춘다. Firebase price/value/purchase_started를 여기에 더하지 않는다. SDK 자동 매출과 자체 purchase_completed도 이중 합산하지 않는다.

목표 하루 $1은 30일 합계 $30 이상이다. 관측 가능한 사용자당 수익의 분모는 같은 기간의 사용자 집합을 사용하며 미관측 앱 밖 사용자를 포함한 전체 고객 ARPU라고 주장하지 않는다. 광고 중단 전후는 기간·지역·신규/기존·Pro 구성 변화를 함께 비교한다.

인앱 구매 1,000건 장기 목표는 ASC의 실제 유료 구매/환불 기준으로 추적한다. 최초 유료 취득과 구독 갱신을 각각 표시하고, 체험·복원·시도 횟수를 구매 건수로 바꾸지 않는다. 갱신을 포함한 거래 목표인지 신규 유료 전환 목표인지 사업 보고에서 정의를 명시한다.

기존 lock_screen_template_changed의 template과 다른 이벤트의 template_id는 분석 시 COALESCE(template_id, template)로 정규화한다.

실행 예시는 queries/behavior-and-retention.sql에 있다. 프로젝트/데이터셋은 실제 이름으로 치환하고 원본/전송 시각을 함께 보관한다. 전송 지연으로 수치가 바뀔 수 있어 당일 값은 잠정, 최소 3일 뒤 재집계와 장기 지연 별도 패널을 권장한다.
