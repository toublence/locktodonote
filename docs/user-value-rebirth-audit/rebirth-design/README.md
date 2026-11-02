# LockTodoNote 재탄생 상세 설계

2026년 10월 30일 재검토 반영. 제품 목표는 **사용자가 지금 중요한 할 일을 잠금화면에서 계속 확인하고, 앱을 열지 않아도 편리하게 완료하는 경험**이다. 기존 디자인과 빠른 작성·표시 조작을 유지하고, 실제 혼동과 중단을 줄이는 최소 변경으로 범위를 좁혔다.

**원안 그대로 개발하지 않는다.** ‘먼저 표시 3개’와 일괄 화면 재배치는 보류·철회했다. 기존 기능으로 해결할 수 있는 부분과 아직 해결하지 못한 누적 표시 문제를 구분한다. 현재 개발 범위는 [최소 변경 설계](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/06-revised-minimal-design.md), 판단 근거는 [기존 사용자 경험 검토](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/05-user-experience-review.md)를 우선한다. 문서만 보완했으며 앱 코드·UI·자료·구매 권리는 수정하지 않았다.

## 문서와 화면안

| 파일 | 판단할 내용 |
| --- | --- |
| [기존 사용자 경험 검토](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/05-user-experience-review.md) | 일곱 질문의 답, 원안의 문제와 유지·수정·제외 판단 |
| [최소 변경 설계](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/06-revised-minimal-design.md) | 재검토 후의 개발 기준. 기존 디자인과 빠른 사용을 보존 |
| [핵심 경험과 표시 규칙](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/01-core-experience.md) | 원안 기록. 현재 기준은 최소 변경 설계 우선 |
| [화면과 변경 전후 흐름](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/02-screens-and-flows.md) | 원안 기록. 화면 재배치와 새 작성창은 개발 대상 제외 |
| [기능과 무료 Pro 및 광고](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/03-features-pro-and-ads.md) | 원안 기록. 권리 보존과 핵심 보호는 유지, 변경 범위는 보완안 우선 |
| [개발 순서와 검증 및 지표](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/04-delivery-validation-metrics.md) | 검증·지표 참고. P0/P1과 사용자 과제는 보완안으로 조정 |
| [화면 변경안](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/screen-proposal.html) | 이전 정적 시안. 기존 디자인 유지 원칙에 따라 현재 구현 기준에서 제외 |

[이전 화면안 미리보기](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/rebirth-design/screen-preview.png)는 원안의 비교 기록이다. 새 디자인 개발이나 전면 재배치의 기준으로 사용하지 않는다. HTML 화면안에도 같은 상태를 명시했다.

## 재검토 후 결정

| 분류 | 결정 |
| --- | --- |
| 유지 | 기존 화면·템플릿·직접 조절·인라인 작성·앱 밖 완료·구매/연결/반복/자동 전환 |
| 개선 | 작성 유형 전환의 표시 부작용, 핵심 흐름 광고/제안, 구성 저장 바로가기·완료 취소 발견성·안내 |
| 수정 | 모든 메모를 저장만 하게 하던 원안을 바꾸고, 표시 중 내용 갱신과 빠른 교체 경로를 보존 |
| 제외 | 별도 3자리 중요 그룹·예약 자리·전역 적용·새 기본 정렬·기본 보기의 자동 전환 전체 끄기 |
| 보류 | 기존 선택으로 해결되지 않는 기본 무료 표시와 수용량 초과의 순서 조정. 실제 사용자 과제 뒤 필요 최소 범위 판단 |

기존 선택은 범위 필터이므로 모든 중요한 항목의 선두 유지를 보장하지 않는다. 이 미해결 요구를 안내 보완만으로 해결됐다고 표현하지 않는다.

## 근거와 해석 순서

요청한 조사 보고서 01~06을 모두 반영했고 전체 평가 README도 참고했다.

| 조사 자료 | 설계에 반영한 내용 |
| --- | --- |
| [01 기능별 평가](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/01-feature-inventory.md) | 입력·반복·개인화·연결·설정 전체 기능의 유지와 개선 범위 |
| [02 사용자 시나리오](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/02-user-experience.md) | 메모 작성의 표시 전환, 누적 시 밀림, 설정 단계, 광고 중단 |
| [03 재사용과 수익](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/03-retention-pro-revenue.md) | 앱 실행과 앱 밖 이용의 분리, Pro 지속 가치, 30일 $30 목표 |
| [04 재탄생 방향](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/04-rebirth-direction.md) | 기존 기능의 개선·통합 우선, 신규 기능의 필요성 제한 |
| [05 증거와 한계](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/05-evidence-and-gaps.md) | 실행본과 소스의 차이, 실기기·경과 시간·거래의 미검증 범위 |
| [06 후속 실사용](/Users/nam/projects/ios/locktodonote/docs/user-value-rebirth-audit/06-continuation-evidence.md) | 앱 밖 완료 성공, 실제 항목 필터, EventKit 원본 완료, 두 유료 결과 문제 |

01의 끝부분에는 ‘앱 밖 완료 성공 검증이 남았다’는 초기 문장이 남아 있으나, 구체적인 후속 U21·U26·U41의 성공 기록과 최종 README를 기준으로 판단한다. 완료 기능을 다시 만드는 과제로 취급하지 않는다. 조사 당시 바이너리는 1.2.0 빌드 20이며 현 소스와 동일하다고 확정할 수 없다. 이후 구현은 실제 배포 대상과의 차이를 먼저 확인해야 한다.

## 최종 사용자 판단

원안 그대로라면 익숙한 조작이 바뀌고 관리할 설정이 늘어 기존 사용자에게 더 편리하다고 단정하기 어렵다. **기존 디자인과 빠른 사용을 유지하면서 원치 않는 표시 전환·광고 중단·막힌 설정·저장 불신을 줄이는 보완안이라면 계속 사용할 이유가 있다.**

완료·반복·날짜 변경·원본 연결·구매 권리 보존은 실제 기존 설정을 가진 설치본에서 검증해야 한다. 새로운 앱 실행 횟수나 설정 화면 방문 증가를 사용자 가치 개선으로 대신하지 않는다.
