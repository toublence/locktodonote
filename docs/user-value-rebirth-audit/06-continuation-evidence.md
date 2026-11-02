# LockTodoNote 추가 실사용 관찰

2026년 10월 30일. 초기 기록 이후 이어서 확인한 실사용 결과다. U16~U43의 구체적인 동작과 한계를 기록한다.

## 추가 실행 환경

`Steady Release Compact`는 iPhone 13 mini / iOS 26.1이다. 이 기기에는 LockTodoNote가 없었으므로 기존 1.2.0 빌드 20을 새로 설치했다. 기존 Steady 앱과 그 저장 자료는 변경하지 않았다. 이후 정상 첫 실행과 온보딩을 진행했다.

무료 기능을 먼저 사용한 후, 이 새 테스트 설치본에서만 기존 DEBUG 지원의 `-device-qa -qa-entitlement pro` 실행 인수로 Pro를 모의 적용했다. 초기화·데이터 시드 인수는 사용하지 않았다. StoreKit 구매·무료 체험 시작·복원을 실행하지 않았다. 테스트 후 인수 없이 다시 실행하여 설정에 ‘Pro 사용하기’가 표시되는 것을 확인했다. 이때 앱 내 24시간 템플릿 체험 안내도 보였으므로 그 이후를 체험 없는 최초 무료 상태로 간주하지 않는다. 실제 사용자 구매 권리는 변경하지 않았다.

## 추가 직접 관찰

| 번호 | 수행 | 결과와 해석 |
| --- | --- | --- |
| U16 | 새 설치 온보딩 전체 진행 | 소개→‘퇴근길 우유 사기’ 작성→잠금화면 표시→준비 완료→빠른 추가 안내 확인. LIVE 시작 성공. 자동화 도구 대기와 환경 복구가 섞여 첫 1분·5분 소요시간 수치로 평가하지 않음 |
| U17 | ‘빠른 추가 설정하기’ 선택 | 단축어 앱의 모든 단축어 화면으로 이동. 잠금화면·액션 버튼 등록까지 자동 완료되는 것은 아님 |
| U18 | 단축어의 ‘LockTodoNote에 추가’ 실행 | ‘Pack umbrella’ 입력 후 할 일에 추가됐다는 응답 확인. 앱에서 동일 항목 표시. 잠금화면 버튼에 배치한 것은 아님 |
| U19 | 앱 복귀 | 테스트 전면 광고 뒤 알림 시간 제안이 이어짐. 광고는 상단 ‘앱으로 이동’으로 닫을 수 있었음. 운영 광고 소재·빈도로 일반화하지 않음 |
| U20 | 앱에서 Pack umbrella 완료→캘린더에서 취소 | 오늘 목록에서 항목 제거. 캘린더에 완료 1개가 남아 있었고 체크를 다시 눌러 미완료 2개로 복귀. 오늘 화면에서 완료 취소보다 캘린더 동선이 더 길었음 |
| U21 | 화면을 켠 잠금화면에서 Pack umbrella 체크 | 앱을 열지 않은 채 카드에서 항목이 사라짐. 앱의 캘린더에서도 완료 1개 확인. 이후 QA 화면의 저장 진단에서 `completedSource=live_activity` 확인. 초기 U12 시도를 완료 기능 실패로 확정하면 안 됨 |
| U22 | 프라이버시를 개수만으로 변경하고 복원 | 미리보기가 `# 1`로 바뀌고 안내 문구도 변경. 모두 표시로 복원. 실제 잠금화면의 모든 프라이버시 모드까지 전수 확인하지는 않음 |
| U23 | 아침 알림 켜기 | iOS 알림 허용 후 오전 8시 선택기가 나타남. 테스트 후 끔. 실제 예약 시간의 알림 수신은 기다리지 않음 |
| U24 | 동기화 및 데이터·언어 화면 사용 | 데이터 화면에는 App Group 보존 설명만 보임. English 선택 시 설정이 즉시 영어로 바뀌며 설정 루트로 돌아감. 시스템 기본값으로 복원 |
| U25 | 위젯 미설치 상태에서 ‘위젯을 추가했어요’ 선택 | 아직 위젯을 찾지 못했다는 안내. 설치 성공으로 잘못 표시하지 않았음 |
| U26 | 시스템 홈 화면 편집→위젯 검색→LockTodoNote 중간 위젯 추가 | 실제 홈 위젯에 퇴근길 우유 사기 표시. 위젯 체크 후 홈 화면을 유지한 채 할 일 없음으로 변경. 이후 저장 진단에서 `completedSource=widget` 확인 |
| U27 | Pro D-Day 저장 | 부산 여행 / 10월 31일로 설정하여 D-1과 목표 이름 표시 확인. 편집에서 저장한 ‘Charger and tickets’는 재진입 시 남아 있었으나 D-Day 카드 메모 영역에는 ‘오늘 메모가 없어요’가 보였음. 표시 불일치 관찰로 기록하고 원인은 분석하지 않음 |
| U28 | 일반 메모와 Pro 혼합 템플릿 | Boarding pass and charger 메모 저장. 혼합 카드에 메모와 할 일 영역이 함께 보임. 메모는 카드에서 짧게 생략되어, 짧은 행동 지침과 긴 내용의 차이가 큼 |
| U29 | 할 일 12개 누적 작성 | 12개 미완료·기존 완료 2개·메모 1개 상황 재현. 새 항목이 먼저 표시되고 카드에는 앞의 최대 5개가 보임. 먼저 적은 Send proposal 등은 카드에서 밀림. 수개월 기록·수천 항목 성능 검증은 아님 |
| U30 | 고급 반복의 조건 목록과 N일 간격 사용 | 요일 조합·매월 마지막 요일·격주·N일 간격 선택지 확인. 매 3일마다로 Water plants 저장. 자동화 목록에 해당 규칙과 오늘의 다음 일정 표시. 다른 반복 3종의 날짜별 발생을 모두 실행한 것은 아님 |
| U31 | 처음 자동 전환 규칙 추가 | 먼저 구성을 저장하라는 안내를 받아 이전 화면으로 돌아가야 했음. 기능 가치와 별개로 초기 설정의 단계 부담을 직접 경험 |
| U32 | Work 구성 저장→평일 09~18시 Work hours 규칙→Water plants와 Read report만 선택→전환 켜기 | 현재 시간의 카드가 선택한 두 항목으로 좁혀짐. 전체 할 일 저장 목록은 유지. 전환을 다시 끄면 일반 표시로 복귀. 앱이 종료된 채 정확한 시각에 전환하는 것은 미검증 |
| U33 | 실제 EventKit의 테스트 미리알림 생성·가져오기·완료 | DEBUG QA 버튼으로 `[LockTodoNote QA] C07FD4AC` 목록의 테스트 항목을 준비하고 가져옴. 앱에서 QA Apple Reminder 완료 후 QA 원본 확인 버튼이 ‘QA source completed’를 표시. 기존 개인 미리알림을 완료하지 않음 |
| U34 | 일반 미리알림 연결 해제·재연결 | 자동 동기화 끄기→일반 연결 버튼으로 다시 연결. 선택했던 QA 목록이 유지됨. 테스트 후 다시 연결 해제. iCloud나 다른 실제 기기 동기화는 미검증 |
| U35 | Pro 날짜 템플릿 | 큰 날짜와 현재 할 일 다섯 개가 보이는 형태로 전환 확인. 달력형보다 단순한 날짜 맥락을 제공 |
| U36 | Pro 사진 템플릿 | 시스템 사진 선택기에서 꽃 사진을 골라 사진과 할 일 카드 표시 확인. 접근성 버튼 활성화와 화면 직접 탭의 결과가 달라, 최종 화면 직접 탭 경로로 적용 성공을 확인 |
| U37 | 사진 구성 Personal 저장 시도 | 사진은 보였지만 구성 저장에서 ‘구성의 사진을 읽을 수 없습니다. 사진을 다시 선택하세요.’ 오류. 반복 수정·원인 분석은 하지 않음. 유료 개인화 결과를 다시 쓰려는 흐름을 막는 문제 |
| U38 | 저장된 Work 수동 적용 | 사진 템플릿 상태에서 기존 Work를 눌러 메모+할 일 템플릿으로 복귀. 두 번째 사진 구성 저장은 성공하지 못했으므로 Pro 여러 구성 전 과정을 통과했다고 하지 않음 |
| U39 | 잠금화면 길게 누르기→사용자화→위젯 추가 | 실제 잠금화면 위젯 갤러리에 도달. 보이는 목록에서 LockTodoNote를 찾지 못했고 제어 도구의 목록 스크롤도 완료하지 못함. 편집 취소. accessory 위젯 설치·표시 성공은 미검증이며 앱에 위젯이 없다고 단정하지 않음 |
| U40 | iPhone 17 Pro Max 홈 화면의 Dynamic Island | 남은 개수 3 표시 확인. 길게 눌러 펼친 화면에 날짜·항목 요약·우유 사기 완료 버튼 확인 |
| U41 | Dynamic Island 확장에서 우유 사기 완료 | 앱을 열지 않고 축소 개수가 3→2로 변경. 홈 위젯에서도 우유 사기가 빠지고 물 마시기·기존 QA 항목만 남음. 기존 Keep this task는 변경하지 않음 |
| U42 | 무료의 잠긴 D-Day 템플릿 선택·제목 개인화 | 결제 전 미리보기에서 Busan trip으로 제목을 바꾸자 D-12 카드에도 반영. 미리보기·구매 후 적용 안내가 구분되어 있음 |
| U43 | 개인화 미리보기에서 Pro 안내 진입·평생 상품 펼치기 | 개인화 카드가 결제 안내에 이어지고 목적별 제목 표시. 연 $4.99·월 $0.99·평생 $9.99가 보임. 시뮬레이터 표시이며 운영 지역별 가격·자격을 확정하지 않음. 구매 없이 닫음 |

## 입력 및 도구 제약

긴 여러 줄 영어 입력은 자동화 도구가 표시한 문자열과 실제 저장 결과가 달라 누적 작성에 사용하지 않았다. 누적 시나리오는 짧은 항목을 UI에서 한 개씩 저장하여 만들었다. 이 입력 도구 문제를 앱의 여러 줄 기능 오류로 기록하지 않는다. 앞선 한국어 3개 입력·저장 결과는 실제 화면에서 별도로 확인했다.

글자 크기 슬라이더는 접근성 값과 실제 표시 비율이 일치하지 않는 도구 조작이 있었고 정상 조절 완료로 집계하지 않았다. 다른 Simulator 창이 전면으로 바뀌는 경우 평가 대상 기기를 다시 선택한 뒤 조작했다. DEBUG 진단 오버레이가 가리는 영역은 실제 제품 UI의 공간 문제로 평가하지 않는다.

## 주요 화면 증거

- [온보딩 시작](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/09-onboarding-intro.png), [단축어 추가 성공](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/12-shortcut-added.png)
- [잠금화면 완료 전](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/14-lockscreen-before.png), [완료 후](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/15-lockscreen-completed.png), [캘린더 완료 기록](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/16-completion-in-calendar.png)
- [홈 위젯](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/17-home-widget.png), [Dynamic Island 확장](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/05-island-expanded.png), [완료 후 개수 2](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/06-island-count-2.png)
- [할 일 누적 상태](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/19-accumulated-todos.png), [전환 항목 선택](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/20-switching-rule-selection.png), [두 항목으로 좁혀진 결과](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/21-switching-result.png)
- [Apple 원본 완료 확인](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/23-reminders-source-completed.png)
- [D-Day 저장 메모](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/18-dday-saved-note.png), [사진 적용](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/25-image-template.png), [사진 구성 저장 오류](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/26-image-profile-save-error.png)
- [개인화 미리보기](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/07-pro-personalized-preview.png), [목적별 결제 안내와 상품](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/08-pro-context-paywall.png)

[전체 캡처 모음](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/evidence/contact-sheet.jpg)은 축소 비교용 이미지다. `27-unrelated-ipad-capture.png`는 다른 시뮬레이터 창이 전면에 있던 때의 캡처이므로 LockTodoNote의 평가 근거에서 제외했다. Pro 테스트 이미지의 QA 진단 오버레이는 운영 앱 화면에 포함되지 않는다.
