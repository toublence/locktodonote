# 앱 내부·잠금화면·위젯 행동 분석 계약

## 행동과 저장 단계

| 관측 | 대표 이벤트 | 인정할 의미 |
| --- | --- | --- |
| 앱 내부 저장 완료 | todo_created/memo_created, todo_completed source=app/calendar | 영속 저장 성공. 자동 반복 생성은 사람의 신규 작성으로 세지 않음 |
| 잠금화면 완료 | todo_completed source=live_activity | 사용자가 Live Activity 완료 버튼 실행, pending_saved |
| Dynamic Island 완료 | todo_completed source=dynamic_island | 전용 expanded 버튼에서 전달하는 출처. 잠금화면과 합산/분리 가능 |
| 홈 위젯 완료 | todo_completed source=widget | 위젯 버튼이 전달한 출처. timeline 호출과 별개 |
| 단축어 추가 | shortcut_quick_add | pending 저장 성공. 화면 갱신 실패 quick_add_failed가 동시에 있어도 저장 실패와 동일시 금지 |
| 외부 작업 최종 저장 | l122_external_commit | action=add/complete, storage_stage=card_file, result=success/unresolved. 새 원본 UUID로 대응. 기존 UUID 없는 추가는 개별 연결 불가 |
| 앱을 여는 행동 | Firebase 자동 session_start, 기존 opened/app_returned 계열 | OS callback이나 큐 전달을 사람이 앱을 연 것으로 변환하지 않음 |
| 자동 갱신/가져오기/후보 계산 | widget_timeline_requested, activity_updated, reminder_import, display_overflow | 기술·상태 진단. 직접 행동 DAU/리텐션에서 제외 |

외부 완료의 UUID가 최종 commit success와 맞으면 ‘최종 저장 확인된 앱 밖 완료’다. commit이 없으면 실패라고 단정하지 않고 아직 앱에서 병합/전송을 관측하지 못한 상태로 분리한다. 파일에 대상이 없으면 unresolved다. 같은 버튼의 이미 제거된 항목 재실행은 새 완료를 만들지 않도록 방어했다. OS가 두 프로세스에서 동시에 실행하는 극단적인 경쟁까지 exactly-once라고 보장하지 않는다.

첫 실제 완료 이벤트는 첫 **관측** 완료이며, 더 늦게 전달된 과거 행동을 기준으로 플래그를 소급 변경하지 않는다. 첫 완료 시간의 주 분석은 내보낸 이벤트에서 최초 원본 시각을 다시 계산한다. 전송 지연이 긴 앱 밖 사용자일수록 즉시 보고가 불완전하다.

## 시각·버전·중복

- 일반 직접 이벤트의 occurred_at_ms는 호출 시각이다. 확장 원본은 큐 생성 시각이고 forwarded_at_ms는 앱 전달 시각이다.
- external_commit의 occurred_at_ms는 파일 처리 시각, action_occurred_at_ms는 원래 외부 행동 시각이다. 이 이벤트의 origin 버전은 commit을 수행한 코드 버전이며 원래 버튼의 버전은 대표 원본 이벤트에서 읽는다.
- app_version/app_build/analytics_release는 전달 앱의 정보다. 원본이 있는 확장 행동의 버전 비교에는 origin_*를 사용한다. unknown_legacy는 최신 원본으로 분류하지 않는다.
- event_id는 고카디널리티 UUID다. Custom Dimension으로 등록하지 않고 내보내기에서만 조인/중복 제거한다. 같은 사용자·event_name·event_id의 재전송만 제거한다.
- Firebase 기본 날짜/DAU/리텐션은 앱의 나중 전달로 원래 행동 날짜로 교정되지 않는다. GA 기본 보고서와 원본 시각 기반 제품 보고서를 따로 둔다.
- 앱을 다시 열지 않아 미전송된 큐, 상한 폐기, SDK 전송 실패는 관측 손실이다. 원본 시각을 복원해도 전체 사용자를 완전하게 복원한 수치는 아니다.

## ‘중요한 일이 밀림’ 분석

candidate_bucket은 현재 날짜·현재 규칙 범위에서 계산한 후보 수 구간이다. capacity_bucket은 Live Activity의 코드상 최대 행 수 구간(기본 4, 큰 글자 3, 해당 템플릿/표시 유형에 할 일 행이 없으면 0)이다. payload_capacity=5와 구분한다. 실제 기기 폭·텍스트·OS 배치에 따른 잘림은 이 값보다 작을 수 있다. 작은 위젯/Island의 실제 수용량을 이 수치로 대체하지 않는다.

overflow는 해당 코드 상한 초과이며 ‘중요한 일 누락’이나 ‘실제 잠금화면 노출 실패’의 증거는 아니다. 개인정보 모드의 후보는 unknown이며 overflow를 생략한다. 후보 상태 변경이 없는 자동 발행은 중복 기록하지 않으므로 이벤트 수를 노출 수로 쓰지 않는다.

selection 이벤트는 저장 성공한 전체/개별 범위다. new_item_scope는 새 앱 작성 항목이 현재 규칙의 범위 안에 있는지 계산한 값이며 날짜·수용량 통과를 보장하지 않는다. 후보 초과와 이후 반복적인 선택 변경이 함께 보이면 기존 선택 UI의 발견성/유지 부담을 실제 사용자 과제로 확인한다. 어떤 할 일이 중요한지는 로그로 추정하지 않는다.

## 1.2.3 비교 규칙

l122_ 접두어는 최초 도입 이름이지 분석 대상을 영구히 1.2.2로 제한한다는 뜻이 아니다. 1.2.3에서도 이름·enum·저장 단계·취소 정의를 유지하고 analytics_release와 앱/확장 버전만 갱신한다. 정의 변경이 필요하면 별도 schema/measurement를 명시한다. 서로 다른 release/cohort/관측 성숙도를 섞어 개선 효과로 발표하지 않는다.
