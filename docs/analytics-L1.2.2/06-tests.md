# 실제 기기 및 테스트 결과

2026-10-31 갱신. 최신 실행 결과·바이너리 해시는 verification.json과 evidence의 요약 파일을 기준으로 한다.

## 실행

- iOS 시뮬레이터 앱 테스트: Analytics 기존 계약·P0/P1 메모 기본값·새 릴리스/속성 상한·원본 시각·캡처 중복·기술 이벤트 제한·최종 저장 후 첫 완료·단축어 메타데이터 호환을 검증했다. 최종 31개/7개 suite 통과. verification.json에 로그를 기록했다.
- 공유 패키지 큐 회귀: `swift test --package-path Packages/LockTodoNoteShared --filter AppGroupQueueTests`, 6개/2개 suite 통과. 개인 자료 대신 독립 테스트 suite 사용.
- iOS Release ARM64 build: 실제 iphoneos SDK로 컴파일했다. Apple Development 서명 Release 빌드와 iPad 업데이트 설치까지 성공했다. App Store 배포 서명 Archive 검증 완료를 의미하지 않는다. 본체·위젯·공유 확장 Info.plist의 버전/빌드 일치를 확인했다.
- 최초 새 계약 테스트에서 25개 속성 상한 초과를 발견했다. 선택적 기존 별칭/기기 컨텍스트를 우선 제외하고 필수 식별 정보를 보호하도록 수정한 뒤 재검증했다. 실패한 최초 로그를 통과 증거로 사용하지 않는다.

## 시뮬레이터 직접 사용

기존 QA 전용 iPhone 17 Pro Max iOS 26.1 인스턴스에서 일반 실행했다. 조작 전에 App Group을 /tmp/locktodonote-L122-baseline/qa-before-manual에 백업했으며 데이터를 초기화하지 않았다.

1. 기존 ‘퇴근길 우유 사기’ 항목이 유지됐다.
2. 오늘에 Smart Repeat 설정/자동 인식 토글이 없고 설정에는 문장 자동 인식 ON 및 기존 Pro 편집기가 표시됐다. [실제 설정 화면](evidence/smart-repeat-settings.png).
3. 인라인에서 새 QA 할 일 작성·저장·앱 내부 완료를 수행했다. 별도 작성 화면이나 적용 단계가 추가되지 않았다.
4. 시스템 잠금화면의 실제 Live Activity에서 기존 QA 항목을 앱을 열지 않고 완료했다. 카드에서 항목이 사라지고 카드 파일에 isDone=true/completedSource=live_activity로 저장됐다. 이 단계의 QA 카드 2개가 남아 있고 새 항목의 완료 출처는 app였다.
5. 최종 빌드의 캘린더에서 메모로 유형을 바꾸고 기록을 저장한 뒤 오늘로 복귀했다. 기존 할 일 표시를 유지했고 새 메모는 기록용으로 저장됐다. 최종 QA 데이터는 카드 3개다.
6. 수행한 핵심 경로에서 전면 광고/자동 제안이 보이지 않았다. AdPolicy.isEnabled=false를 유지했다.

이전 1.2.1에서 확인했던 사진/D-Day/30개 누적/미리알림 원본 완료 증거는 docs/rebirth-p0p1-2026-10-30/에 보존했다. 이를 이번 1.2.2 실기기 재검증 성공으로 바꿔 쓰지 않는다. 이번 로그 부착으로 기존 반복·날짜·이월 알고리즘을 재작성하지 않았다.

## 로컬 StoreKit 검증 (10월 31일)

독립 UserDefaults suite와 임시 StoreKit 구성으로 기존 lifetime 상품 ID의 Xcode 로컬 거래를 확인했다. 실제 상품 가격 변경·실계정 결제는 없다. 검증 거래 environment=xcode, 구매 후 Pro 활성화, restore=restored, 서비스 재생성 시 캐시 유지, 환불 후 권리 회수까지 통과했다. 거래 반영은 비동기이므로 최대 2.5초 안에 권리 갱신을 기다렸다. 테스트 중 Firebase 수집을 잠시 끄고 자신의 로컬 거래만 제거했다. 사용자 거래/카드는 초기화하지 않았다. 이는 실제 구독·무료 체험 청구·기존 유료 고객의 복원 증거를 대신하지 않는다.

최종 로그 `/tmp/locktodonote-L122-storekit-propagation.log`: 31개/7개 suite 통과. 기존 실패 실행은 통과 증거로 쓰지 않는다.

## iPad와 콘솔 후속 검증

물리 iPad Air 11 M2, iPadOS 26.6.2에서 기존 1.2.0(20) 위에 서명된 1.2.2(22)를 업데이트 설치했다. 초기화/삭제 설치를 하지 않았다. 초기 5개 카드의 ID·내용·체크리스트·완료·반복·표시 플래그는 유지됐으며 변경 필드는 targetDateTime/updatedAt뿐이다. 날짜 이월의 예상 변동과 데이터 손실을 구별한다. 원본 백업은 비공개 로컬 폴더에만 있다.

사용자 인증/USB 연결 후 설정·할 일 작성/완료/취소/재실행·기록용 메모 시나리오를 통과했다. 실제 시스템 Live Activity 완료의 최종 저장도 확인했다. 전체 UI suite는 Mac 공간 소진으로 중단됐으며 앱 복귀 화면 확인은 미완료다. 테스트 자료는 정리했고 기존 5개 카드를 재확인했다. 세부 결과와 제한은 [후속 검증](08-final-validation-2026-10-31.md)을 따른다.

Firebase/GA에서 실제 iPad 이벤트 및 공통 릴리스 4개 값의 DebugView 수신을 확인했다. 전수 행동/확장 이벤트의 중복 여부까지 모두 검증한 것은 아니다. GA 맞춤 측정기준 30개를 등록했고 ASC의 최신 빌드 21 및 22 부재를 관찰했다. BigQuery 쿼리 실행과 실제 수익 대조는 미실행이다.

## 미검증

연결된 기기는 iPad Air M2이며 실제 iPhone은 없다. iPhone 1.2.0→1.2.2 업데이트, 실제 홈 위젯/Island 완료, 날짜/시간 경계, 사진/D-Day, 기존 실제 유료 권리/복원은 실기기 최종 미검증이다. iPad를 iPhone 통과 증거로 대체하지 않았다. 실제 결제·사용자 데이터 초기화·App Store 업로드·심사 제출을 하지 않았다.

