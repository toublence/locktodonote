# LockTodoNote iPad 실기기 테스트 결과

2026년 10월 21일, 연결된 iPad Air 11인치 M2에서 Firebase 계약 테스트 17개와 핵심 UI 테스트 1개가 통과했다. 실제 Google 테스트 배너 노출과 Pro 상태의 광고 차단을 확인했다. 잠금화면 표시·갱신·탭 테스트는 Mac 디스크 부족으로 실행하지 못했다.

## 기기와 실행 조건

- 기기: iPad Air 11인치 M2, iPad14,8, iPadOS 26.6.2.
- 설치·테스트: 개발 서명 Debug, 앱 1.1.8 build 18. 운영 광고가 아닌 Google 공식 테스트 광고 ID 사용.
- 실제 구매·ATT 허용·동의 양식 자동 승인은 수행하지 않았다. 무료/Pro 광고 적격성은 Debug 전용 QA 권한 오버라이드로 검사했다.
- 기존 데이터를 초기화하지 않았다. App Group 카드·환경설정·구성 파일을 기기와 로컬 비공개 경로에 보존하고, UI 테스트 종료 시 QA 변경을 복원했다.
- 최초 UI 실행의 중복된 Save 선택자는 테스트 코드의 문제였다. 편집 저장 버튼에 고유 접근성 식별자를 부여한 뒤 동일 흐름을 재실행하여 통과했다.

## 검사 결과

| 상태 | 항목 | 실제 확인 결과 |
|---|---|---|
| PASS | 서명·설치·실행 | 기존 1.1.4 위에 개발 서명 1.1.8을 설치하고 테스트 러너 실행 |
| PASS | Firebase 이벤트 계약 | AnalyticsServiceTests 17개 통과. 위젯 구성 변경·삭제·오류 보존, 최초 생성, 수익 분리, 확장 큐 전달 포함 |
| PASS | 할 일 생성 | 기존 데이터 위에 고유한 QA 할 일 생성, 저장 파일에서 확인 |
| PASS | 할 일 수정 | 해당 QA 항목의 편집과 저장 확인 |
| PASS | 앱 재실행 | 수정한 QA 항목이 앱 종료·재실행 뒤에도 유지 |
| PASS | 할 일 삭제 | 생성한 QA 항목 삭제 후 저장 상태에서 제거 확인 |
| PASS | 할 일 완료 | 별도 QA 항목 완료 후 isDone=true 확인 |
| PASS | 설치 안내 | 실제 iPad에서 위젯 탭·미리보기·잠금화면 설치 단계·설치 확인 버튼 표시 확인 |
| PASS | 배너 실제 노출 | 무료 QA 상태 Calendar에서 ad_impression_observed 콜백과 Test mode 배너 화면 확인 |
| PASS | Pro 광고 차단 | Pro QA 상태에서 eligible=false와 Calendar 배너 부재 확인 |
| PASS | 홈 화면 위젯 구성 조회 | 사용자 위젯 추가 후 최종 OS 관측 signature=1:0:0, state=home_only |
| PASS | 원본 내용 보존 | 원본 카드 ID·내용·완료 상태 5개 모두 보존, 구성 파일 바이트 일치. QA 항목과 권한 오버라이드 제거 |
| BLOCKED | 잠금화면 실제 표시·갱신·탭 | 전용 테스트의 두 빌드 시도가 Mac의 No space left on device로 중단. 테스트 본문 미실행 |
| BLOCKED | 잠금화면 구성 확인 | 마지막 조회는 홈 화면 1개·직사각형 0개·inline 0개. 사용자의 추가 완료 응답과 별개로 잠금화면 설치 성공을 확인했다고 보고하지 않음 |
| BLOCKED | UMP·ATT 전체 상태 | 실제 동의/거부/제한 조합, 개인정보 선택 변경, No Fill·실패 주입은 이번 실행 범위에 포함되지 않음 |
| BLOCKED | 기타 OS 시나리오 | 재부팅·App Store 배포 업데이트·여러 위젯·잠금 중 가림·빈 목록·긴 글의 실제 위젯 렌더링은 미검증 |

성공한 핵심 UI 테스트는 `test10RetentionCRUDGuideAndTestBannerWithoutReset`이며 약 48초 동안 실행됐다. 이 시간은 자동화 전체 실행 시간이며 신규 사용자의 첫 입력 시간이나 설치 소요 시간으로 해석하지 않는다. 테스트 배너 수익·노출은 운영 광고 실적에 합산하지 않는다.

## 데이터 보존

원본 카드 5개와 복원 후 카드 5개의 ID, 제목·본문·체크리스트 내용·완료 상태가 일치했다. 파일 전체는 동일하지 않다. 기존 미완료 이월 기능이 정상 실행되면서 targetDateTime이 10월 17일에서 10월 21일로 바뀌었고 updatedAt도 갱신됐다. 변경 필드는 이 두 가지뿐이다. 저장된 구성 파일은 원본과 바이트 단위로 일치했다.

기기 내 QA 백업 파일은 복원 후 제거됐고 마지막 실행은 QA 인자 없는 일반 앱 실행이다. 사용자가 추가한 홈 화면 위젯은 유지했다. 이후 실제 위젯 구성 감지에 따른 기존 앱의 활성화·체험 보상 처리는 정상 앱 동작이며 QA 권한 강제가 아니다.

원본 사용자 데이터와 스크린샷·xcresult는 저장소에 복사하지 않고 `/Users/nam/.codex/tmp/locktodonote-ipad-retention-20261021-1333/`에 보관했다. 스크린샷에는 기존 할 일 내용이 포함될 수 있다. 저장소의 검증 JSON에는 원본 본문을 포함하지 않는다.

## 추가 확인이 필요한 사항

Mac 여유 공간 부족으로 컴파일 캐시를 한 차례 정리한 뒤 재시도했으나 다시 실패했다. 실패한 빌드의 임시 컴파일 캐시는 정리했고, 통과한 테스트 기록·원본 백업·스크린샷은 보존했다. 공간을 충분히 확보한 뒤 전용 `test11InstalledLockWidgetRefreshAndOpenWithoutReset`을 실행해야 한다. 이 테스트는 잠금화면 계열 구성이 실제로 감지되어야 진행한다.

최신 기기 빌드는 본앱 build 18과 확장 build 14의 불일치 경고가 있었다. 개발 설치와 위 테스트는 통과했지만 배포 전 CFBundleVersion을 통일해야 한다. 테스트용 심볼 생성을 끈 명령에 따른 Crashlytics dSYM 경고도 있었으며, 이를 Release 심볼 업로드 성공으로 해석하지 않는다.

앞선 공유 패키지 전체 테스트의 assertion 3건 실패는 이번 iPad의 선택된 17개 계약 테스트와 별개다. 전체 테스트가 모두 통과했다고 보고하지 않는다.

## 저장한 증거

- `ipad-retention-qa-2026-10-21/device-tests.log`: 최초 실행과 이벤트 계약 17개 통과.
- `ipad-retention-qa-2026-10-21/retention-retry.log`: 핵심 UI 테스트 통과, 실제 테스트 광고 노출·Pro 차단 기록.
- `ipad-retention-qa-2026-10-21/data-preservation.json`: 데이터 비교 결과. 날짜 갱신 때문에 전체 의미 동일성은 false이며, 내용·완료 보존 검사는 true.
- `ipad-retention-qa-2026-10-21/widget-configuration-final.json`: 최종 관측된 홈 화면·잠금화면 구성 상태.
- `ipad-retention-qa-2026-10-21/widget-device.log`, `widget-device-retry.log`: 디스크 부족으로 중단된 위젯 검증 빌드 기록.
