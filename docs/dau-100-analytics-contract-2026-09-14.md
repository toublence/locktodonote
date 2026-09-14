# LockTodoNote 성장 측정 계약 — 제안, 구현 전

작성일: 2026-09-14. 연결 문서: [DAU 100 분석](/Users/nam/projects/locktodonote/docs/dau-100-analysis-2026-09-14.md).

목적은 신규 이벤트 수를 늘리는 것이 아니라 **설치→작성→실제 표시→반복 사용→유료 가치 적용**을 동일한 정의로 측정하는 것이다. 기존 자동 이벤트를 중복 발신하지 않는다. 아래는 코드 변경 명세이며 구현하지 않았다.

## 1. 공통 계약

| 파라미터 | 정의 |
|---|---|
| `analytics_schema_version` | 이번 의미 수정 이후 2. 기존 기간과 혼합 분석 금지 |
| `app_build`, `implementation` | 빌드 번호와 swiftui/flutter 구분. 현행 자동 app_version과 함께 사용 |
| `source` | 실제 발생 위치: onboarding / inline / calendar / live_activity / widget / dynamic_island / shortcut / automatic / settings |
| `template_id` | 기존 template/template_id를 하나로 정규화. 분석용 내부 raw ID |
| `is_premium` | **검증된 유료 권한**. 임시 템플릿 체험을 유료로 세지 않음 |
| `trial_type` | none / template_24h / store_intro. 실제 거래 판단과 UI 대상 판정을 구분 |
| `result` | success / fail / cancelled / pending / skipped 등 이벤트의 실제 결과 |
| `occurred_at_ms` | 확장 행동의 실제 발생 시각. 앱 전송 시각과 분리 |
| `event_id` | 확장 원본 행동의 임의 ID. 큐 병합·전송 중복 제거용, GA 커스텀 차원으로 등록하지 않음 |
| `request_id` / `attempt_id` | Activity 요청 또는 구매 시도 연결용. 필요한 이벤트에만 사용, 고카디널리티 차원 등록 금지 |

기존 공통 필드 `country`는 기기 Locale 지역이므로 실제 사용 국가/Storefront와 혼동하지 않는다. 앱 선택 언어와 기기 언어도 구분한다. `device_family="ios"`는 기기 종류 분류가 아니므로 iPhone/iPad 여부가 필요하면 별도 값으로 보낸다.

모든 이벤트에 모든 필드를 붙이지 않는다. 메모 본문·할 일 텍스트·사진·파일 경로는 분석에 보내지 않는다. 거래 식별/정합성은 별도 거래 기록에서 관리하고 UI 이벤트의 상품 정가를 실제 매출로 합산하지 않는다.

## 2. 기존 이벤트를 유지하며 의미 수정

| 단계·대표 이벤트 | 올바른 발신 시점 | 필수 맥락·수정 |
|---|---|---|
| `first_open` | SDK 자동 수집 | 수동 발신 금지. 설치/재설치 첫 실행 코호트 사용 |
| `onboarding_start` | 온보딩 한 세션의 첫 표시 | `onboarding_started` 별칭 중복 발신 중단. 재시작 세션은 구분 |
| `onboarding_step_view` | 실제 단계 표시 | step/index. 단순 body 재계산은 제외 |
| `onboarding_complete` | 사용자가 온보딩을 종료 | skipped 파라미터 유지. 완료와 핵심 활성화는 별개 |
| `todo_created` | 영속 저장 성공 후 | created_count, is_first_todo, source, recurrence. 첫 Todo 플래그는 이 경로에서만 설정 |
| `first_todo_created` | 실제 첫 Todo 영속 저장 | 기존 지표 연속성용 1회. todo_created와 합산 금지 |
| `memo_created` | 메모 영속 저장 성공 후 | is_first_memo, source, template_id. Todo만 활성화 가능한 정의 보완 |
| `todo_completed` | 사용자가 미완료→완료로 변경하고 작업을 보존한 시점 | source, event_id. 해제는 완료에 포함하지 않음. 큐와 병합 양쪽에서 발신 금지 |
| `top_destination_selected` | 실제 탐색 | destination=calendar로 캘린더 진입 측정. 별도 calendar_view 별칭 불필요 |
| `lock_screen_template_changed` | 실제 템플릿 적용 | template_id, source, access_type. 미리보기 변경과 구분 |
| `lockscreen_preview_seen` | 미리보기가 표시됨 | source를 onboarding으로 고정하지 않음. 실제 잠금화면 조회로 쓰지 않음 |
| `live_activity_start_success` | Activity.request 성공 | request_id, source, template_id, has_user_content, content_type, elapsed_ms. started 별칭 합산 중단 |
| `live_activity_start_failed` | 실제 시도 실패 | 같은 request_id, error_domain/code, reason. 자동/온보딩/수동 source 보존 |
| `lockscreen_setup_confirm_yes/no` | 실제 사용자 응답 | surface=live_activity/widget, confirmation_method=self_report. API 성공 시 자동 yes 발신 제거 |
| `activation_complete` | 영속 저장된 사용자 Todo 또는 Memo가 있고, 그 내용을 담은 표시 등록 성공 또는 검증된 위젯 설정이 완료됨 | activation_definition=content_and_setup_v2, content_type, method, time_to_value_seconds. 등록 도달 지표이며 실제 사용 지표와 분리 |
| `widget_setup_started` | 설치 안내를 실제 열 때 | source, family. ‘추가했어요’ 버튼에서 시작으로 기록하지 않음 |
| `widget_installed_confirmed` | OS 구성 확인 또는 명시된 확인 방식이 완료될 때 | confirmation_method=os_configuration/self_report. timeline 호출은 visibility 증거가 아님 |
| `paywall_seen` | sheet가 실제 보임, 표시 1회당 1회 | paywall_trigger, preview_template, requested_feature, 상품 로딩 상태. 요청과 표시 구분 |
| `plan_selected` | 기본/수동 상품 선택 | is_default 구분. default를 상품 선호로 집계하지 않음 |
| `purchase_started` | 명시적 구매 CTA 후 StoreKit 요청 직전 | attempt_id, trigger, product_id, plan, display_price, currency, intro_eligible |
| `purchase_completed` | 검증된 거래 성공이 앱에 반영됨 | attempt_id가 있으면 연결. 즉시 완료와 delayed update를 모두 포괄하되 중복 제거. 실제 trial 여부는 거래 기준 |
| `purchase_cancelled` | StoreKit 사용자 취소 | result=cancelled. 완료 사용자와 배타적 사용자 집합으로 가정하지 않음 |
| `purchase_failed` | 요청/검증 실패 | result=fail, error_domain/code. 상세 지역화 문자열로 집계하지 않음 |
| `purchase_value_applied` | 구매 목적이던 템플릿/사진/D-Day의 설정 저장 성공 | value_type, apply_result, live_activity_result. 저장 성공과 Activity 성공을 분리 |
| `paywall_dismissed` | 결제 완료 없이 닫음 | dismiss_reason=close/swipe/background 등 판별 가능한 범위. onDisappear 전체를 이탈로 간주하지 않음 |
| `restore_completed` | 복원 요청 결과 | result=restored/no_purchases/fail. fail도 success로 기록하는 현행 수정 |

기존 `pro_template_tapped → pro_info_sheet_viewed → pro_preview_viewed`는 선택→시트→실제 미리보기로 조건이 다르다. 각 표시 시점을 분리하되 단순 합산하지 않는다. `pro_preview_interacted`는 의미 있는 사용자 조작 한 번을 기준으로 하고 선택한 template_id를 전달한다. 현재 동일 숫자는 같은 콜백의 과거 발신과 최신 구현이 섞였을 가능성이 있다.

`widget_timeline_requested`, `lockscreen_activity_updated`, 자동 refresh/restart는 기술 상태 진단용이다. 이를 ‘핵심 사용’이나 ‘활성 사용자’의 자체 지표에 넣지 않는다. `widget_todo_completed` 같은 기존 보조 별칭은 대표 todo_completed와 합산하지 않는다.

## 3. 신규 이벤트는 필요한 행동만

| 신규 이름 | 이유 | 최소 필드 |
|---|---|---|
| `live_activity_start_attempt` | 정확한 요청 분모와 실패율이 없음 | request_id, source, template_id, reason=user_start/foreground_recovery/shortcut |
| `app_returned` | 앱 복귀 당시 내용·경로를 session_start만으로 구분하기 어려움 | 앱의 실제 foreground에서 설치일 이후 하루 1회, cohort_age_days, days_since_previous_foreground, entry_source, activity_state, has_today_content |
| `lockscreen_interacted` | 완료 외 날짜/메모·Todo 전환도 직접 사용임 | action=select_date/select_content, surface, event_id, occurred_at_ms. 완료는 기존 todo_completed로만 |
| `purchase_pending` | pending을 실패/누락과 구분 | attempt_id, product_id, paywall_trigger |
| `reminder_action` | 기존 로컬 알림 동의·탭 경로가 측정되지 않음 | action=enabled/disabled/permission_granted/permission_denied/opened, kind=morning/evening, source |
| `card_save_failed` | UI 성공과 저장 실패 분리를 확인해야 함 | operation=create/update/merge, source, error_code. 텍스트 내용 제외 |

`app_returned`는 D1 자체가 아니다. D1·D7·D30은 일별 코호트 표에서 계산한다. 기존 `next_day_open`을 되살리더라도 동일 의미의 또 다른 대표 이벤트로 운영하지 않는다. 자동화/위젯 큐 전송은 app_returned를 대신 발신하지 않는다.

알림의 enabled는 일정 등록·권한 상태에 맞춰 기록한다. OS가 실제 전달했다는 확인 없이 scheduled를 delivered로 바꾸지 않는다. 메모 실제 읽기는 검출할 수 없으므로 열린 메모 ID를 분석 서버에 보내 사용량을 만들어내지 않는다. 필요하면 기존 화면 열기/편집 완료에 비식별 content_type으로 별도 판단한다.

## 4. 활성화 상태 수정 규칙

현재 문제 경로:

`빈 Skip → completeOnboarding → ensureLiveActivityStarted → liveActivityStarted → recordActivationSignal → firstTodoCreated=true → activation_complete`

수정 후:

1. Todo/Memo를 저장하는 경로만 각각의 첫 생성 상태와 시각을 기록한다.
2. 성공 요청에는 **그 요청 스냅샷에 실제 사용자 콘텐츠가 있었는지** 기록한다. 나중에 콘텐츠만 추가한 경우에도 해당 내용의 발행 상태를 반영한다.
3. activation은 두 상태를 조합해 신규 정의로 판정하고 한 번만 발신한다. 자동 API 성공은 user_confirmed_widget가 될 수 없다.
4. 실제 핵심 사용은 activation과 별도로 todo 완료, 잠금화면/위젯 진입, 명시적 날짜/내용 선택 등으로 계산한다. 자기확인과 실제 행동도 구분한다.
5. 첫 실행부터의 시간은 최초 foreground의 신뢰 가능한 시각을 쓴다. 이관된 오래된 사용자의 installDate를 새 버전의 첫 가치 시간으로 쓰지 않는다. 기존 사용자에게 시간 원점이 없으면 unknown으로 둔다.
6. 과거 상태를 모두 reset해 신규 활성화가 폭증하게 하지 않는다. schema=2 신규 코호트를 주 분석 대상으로 하고 기존 사용자의 재활성화는 별도 분류한다.

## 5. 확장 큐와 DAU·리텐션

원본 `QueuedAnalyticsEvent.createdAt`과 `event_id`를 전송한다. 처리한 ID만 acknowledge하고 새로운 항목이 들어온 큐 전체를 삭제하지 않는다. 큐의 상한·폐기 건수와 전송 지연을 측정 가능하게 한다. 저장 작업 큐는 영속 저장 성공 후에만 제거한다.

**occurred_at_ms를 추가하는 것만으로 GA4 기본 날짜·DAU·리텐션이 과거 날짜로 교정되지는 않는다.** 전송일 기반 GA4와 원본 시각 기반 제품 행동 보고서를 분리해야 한다. BigQuery 또는 별도 내보내기가 가능할 때 동일 앱 인스턴스의 원본 날짜별 사용자 합집합을 계산한다. 확인되지 않은 BigQuery 연동을 이미 설치된 것으로 전제하지 않는다.

앱을 다시 열지 않은 확장 사용자는 큐가 전달되지 않아 계속 누락된다. 원본 시각을 복원한 수치도 지연·유실 때문에 완전하지 않다. 잠금화면을 수동으로 읽기만 한 사용자는 이 방식으로 관측할 수 없다. 백그라운드 자동 로그를 늘려 Firebase DAU를 인위적으로 만드는 방식은 사용하지 않는다.

추천 대시보드:

| 지표 | 정의 |
|---|---|
| 주 목표 | production 필터의 Firebase DAU, 당일 값과 7일 이동평균 함께 |
| 핵심 행동 사용자/일 | 앱/잠금화면/위젯/단축어의 **직접** 사용자 행동, event_id·사용자·발생일 기준 중복 제거 |
| 첫 가치 도달률 | 신규 first_open 코호트 중 content_and_setup_v2 충족 사용자 / 관측 가능한 신규 사용자 |
| D1/D7/D30 | 각각 해당 일까지 관측 가능한 first_open 코호트 분모와 그 정확한 날 활동한 분자. 아직 도달하지 않은 코호트는 제외 |
| 주간 반복 사용 | 첫 7일 관측이 끝난 신규 코호트 중 서로 다른 3일 이상 핵심 행동 사용자 비율 |
| 재방문 구성 | 해당일 활성 사용자 중 해당일보다 먼저 첫 실행한 사용자. 설치 후 1일 이상이라는 로컬 플래그만으로 확정하지 않음 |
| 유료 전환 | 동일 신규 코호트에서 제한된 기간 내 실제 유료 거래 / 성숙 신규 사용자. 체험 시작·평생·구독 분리 |
| Paywall 퍼널 | source별 동일 사용자/시도에서 seen→started→verified, 시간 순서와 기간 제한 명시 |

Firebase 표준 DAU와 직접 foreground 지표가 다르게 나오면 둘 다 제시하고 정의를 변경해 목표를 달성한 것처럼 보이게 하지 않는다.

## 6. 수익 정합성과 필터

- ASC $18은 proceeds, Firebase $64.52는 다른 수익 집계다. 동일 기간·상품·국가·통화와 gross/net을 대응시킨다.
- 구매 CTA의 정가와 `purchase_completed`의 정가 파라미터는 과금 매출이 아니다. 무료 도입 체험은 특히 구분한다.
- 거래 환경은 검증된 StoreKit 거래 정보에서 확인하고 내부 테스트/개발/프로덕션을 분리한다. 1명의 10회 갱신만 보고 테스트라고 단정하지 않는다.
- 취소·복원·갱신·초기 구독·평생 구매를 별도 지표로 둔다. 자동 수익과 수동 `purchase`를 더해 이중 집계하지 않는다.
- `app_store_subscription_renew`의 원본을 일반 BigQuery 이벤트 export에서 반드시 볼 수 있다고 가정하지 않는다. Google 문서는 이 이벤트가 BigQuery로 export되지 않는다고 설명한다. 필요하면 ASC 거래 자료와 대조한다. [자동 수집 이벤트 정의](https://support.google.com/analytics/answer/9234069?hl=en)

## 7. 후속 구현 완료 기준

아래는 다음 구현의 표적 검증 기준이며 이번 분석에서 실행하지 않았다.

- 빈 Skip과 빈 Activity 성공은 first_todo_created/activation_complete를 만들지 않는다.
- Todo/Memo 영속 저장 실패 시 입력을 잃지 않고 성공 이벤트도 발신하지 않는다.
- 실제 확인 전 confirm_yes가 없고 Live Activity 성공이 위젯 확인으로 기록되지 않는다.
- 잠금화면 Todo 1개 완료→앱 복귀 후 대표 todo_completed 1개, 원본 시각 유지.
- 자동 업데이트 10회는 직접 사용자 행동 10회로 집계되지 않는다.
- 기간과 관측 가능한 분모가 같은 D1/D7/D30 보고서를 만들 수 있다.
- 구매 취소/pending/실패/검증 성공/복원 결과를 구분하고 지연 승인도 최종 결과가 연결된다.
- 권한 변경 직후 App Group isPro와 앱 UI가 일치하고 미리보기 결과 적용 실패는 재시도 가능하다.
