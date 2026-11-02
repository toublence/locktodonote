# 실제 사용 검증 기록

2026-10-30 · 구버전 1.2.0 → 검증 버전 1.2.1 (21)

## 환경과 증거 범위

iOS 26.1 시뮬레이터의 iPhone 13 mini와 별도 iPhone 17 Pro Max QA 인스턴스에서 실제 UI를 조작했다. 구버전 비교용 데이터·파일을 먼저 백업했다. 개인 iPhone은 연결되어 있지 않았으며 목록의 iPad도 사용할 수 없는 상태였다. 실제 iPhone 검증으로 표기하지 않는다. QA 데이터의 영어 입력 일부가 한국어 입력기와 자동화 조합으로 변형된 경우는 앱 저장 오류로 판정하지 않았다.

## 시나리오 결과

| 시나리오 | 관찰 결과 | 증거/판정 한계 |
| --- | --- | --- |
| 할 일 표시 중 메모 유형 선택·저장 | 할 일 표시 유지, 기록용 메모 보존, 기존 표시 메모 유지 | [화면](evidence/05-memo-capture-preserves-todos.png) |
| 혼합 표시에서 새 메모 교체·기존 메모 수정 | 기본 켬으로 저장 1회 교체, 편집 저장으로 내용 갱신. 별도 적용 없음 | [최종 선택 메모](evidence/08-selected-memo-only.png) |
| 기록 전용 메모의 혼합 카드 노출 | 최초 검증에서 재현. 표시 후보 필터 수정 후 선택 메모만 표시, 원본 기록 보존 | 앱 미리보기와 시스템 잠금화면 재확인 |
| 개별 메모 규칙 중 새 메모 | 규칙의 메모 선택은 불변. 입력 토글 끔/비활성 및 이유 표시, 기록 저장 가능 | [화면](evidence/14-rule-memo-scope.png) |
| 미완료 30개 | 기존 입력으로 누적. 기본 최신순에서 중요한 오래된 항목 밀림은 남음 | [30개 상태](evidence/06-thirty-pending.png) |
| 기존 자동 전환의 2개 선택 | 30개 누적 상태에서도 기존 선택 2개만 표시. 시간·선택 확인 후 규칙 원상 복구 | [선택 유지](evidence/07-existing-rule-two-todos.png). 시간 경과 전환 시험과는 구분 |
| 잠금화면에서 완료 | 앱을 열지 않고 QA17 완료, 다음 후보로 갱신. 저장 데이터의 live_activity 완료 출처 확인 | [전](evidence/09-lockscreen-before-completion.png) / [후](evidence/10-lockscreen-after-completion.png). 실표시 공간상 혼합 카드에 할 일 4개 |
| 오늘 완료 취소 | 완료 그룹을 펼치고 체크 해제, 캘린더 이동 없이 복귀 | [화면](evidence/12-today-undo.png) |
| 신규 설치 첫 작성·시작 | 기존 온보딩에서 저장·활동 시작 성공, 오늘로 이동 가능 | [성공 화면](evidence/11-first-start-success.png). 마지막 유지 시간 문구 수정은 최종 빌드 컴파일 확인, 온보딩 전체 재수행은 하지 않음 |
| 구성 없는 자동 전환 | 기존 저장 화면에서 Daily 구성 저장 후 원래 자동 전환 위치 복귀 | [복귀 화면](evidence/13-layout-save-return.png). 무료 상태의 규칙 추가 Pro 안내도 유지, 구매하지 않음 |
| 미리알림 연결·완료 | 권한 허용 후 QA 전용 EventKit 목록 연결. 앱에서 완료 시 원본 완료 확인, 테스트 연결 해제 | [원본 완료 확인](evidence/15-reminder-source-completed.png). 개인 목록을 사용하지 않음 |
| 반복 설정 보존 | 구버전 반복 항목과 선택 식별 보존 | 실제 다음 발생일까지 기다리는 시험은 미수행 |
| D-Day 메모 | 구버전 미리보기의 일반 메모/전용 메모 불일치 재현 후 전용 메모로 수정 확인 | [전](evidence/01-before-dday.png) / [후](evidence/04-after-dday.png). 실제 기기의 D-Day 잠금화면은 미검증 |
| 사진 구성 저장 | 메모 사진 → 할 일 사진 교체 뒤 누락된 비활성 이미지로 저장 실패 재현. 수정 후 저장·재적용 성공, 기존 사진 구성도 재적용 | [기존 오류](evidence/02-before-photo-error.png) / [저장 성공](evidence/03-after-photo-save.png) |
| 광고·자동 제안 | 수행한 작성·완료·복귀에서 전면 광고나 자동 결제/리뷰 제안 없음 | 정책상 앱 오픈 광고 전체 차단. 모든 OS 복귀 원인의 실기기 전수 시험은 아님 |
| 무료·모의 Pro | 무료 잠금 표시 유지, 모의 Pro에서 기존 규칙·템플릿 사용 후 QA 상태 복원 | [정리 후 무료 화면](evidence/16-clean-free-user.png). 실제 결제/복원 미수행 |

## 업데이트 보존 비교

정상 서명한 구버전을 복원하고 백업 자료를 넣은 다음, 정상 서명한 새 앱을 덮어 설치했다. 같은 App Group 컨테이너에서 카드 16개·저장 구성 2개·자동 전환 규칙 1개가 JSON 기준 동일했다. 관련 설정 23개를 보존했다. 구매 캐시 문자열의 키 순서 차이는 JSON으로 비교해 논리 값 동일을 확인했다. 모의 Pro이므로 실제 영수증 검증은 별도다.

검증 중 카드가 35개로 늘었고, 그중 할 일은 32개였다. 잠금화면 완료 직전 미완료 30개/완료 2개, 완료 뒤 미완료 29개/완료 3개였다. 나머지 3개는 메모다. 기존 자동 전환 규칙은 시험 후 원래 값으로 되돌렸다. 별도 신규 설치 QA 인스턴스는 모의 Pro·QA 미리알림 연결을 정리하고 일반 실행 상태로 돌렸다.

초기 unsigned 테스트 산출물 설치는 시뮬레이터 App Group 권한이 없어 컨테이너 유지 시험에 실패했다. 설치 전에 확보한 백업으로 구버전과 자료를 복원한 뒤 위의 정상 서명 업그레이드를 따로 수행했다. unsigned 시도는 보존 성공 증거에서 제외했다. 백업 위치는 `/tmp/locktodonote-rebirth-p0p1-baseline/`이며 저장 공간 정리 대상이 되면 이 보고서만으로 원본을 복원할 수는 없다.

## 코드 검증과 빌드

- 앱 테스트: `LockTodoNoteTests` 20개 통과. 로그 `/tmp/locktodonote-rebirth-p0p1-build.log`, 결과 `/tmp/locktodonote-rebirth-p0p1-tests.xcresult`.
- 공유 패키지: `swift test --package-path Packages/LockTodoNoteShared --filter DashboardComposerTests`의 35개 테스트 통과. 기록 전용 메모 제외·개별 규칙 선택 보존·단축어 설정 독립성 회귀 확인. 기존 테스트의 오래된 단축어 설정 가정은 실제 기존 정책에 맞게 수정했으며 운영 단축어 정책을 변경하지 않았다. 로그 `/tmp/locktodonote-rebirth-p0p1-shared-tests.log`.
- 최종 서명 ARM64 시뮬레이터 빌드 성공. 로그 `/tmp/locktodonote-rebirth-p0p1-delivery-build.log`. 산출물 `/tmp/locktodonote-rebirth-build/Build/Products/Debug-iphonesimulator/LockTodoNote.app`.
- 최종 실행 파일 SHA-256: `e9d2038099e9d8b65c6ea4dedb576052e711b01087245b45839dbde0c2f606dc`.
- 저장 공간 부족과 기본 패키지 캐시 누락으로 중간 빌드가 실패했다. 별도 DerivedData·패키지 경로의 빌드는 성공했고 기본 프로젝트 패키지 해결도 마지막에 성공했다. 의존성 버전을 변경해 우회하지 않았다.

테스트 통과는 실제 iPhone·StoreKit·시간 경계 검증을 대신하지 않는다. 모든 검증을 모든 언어·화면 크기·위젯 표면에서 마친 것은 아니다.
