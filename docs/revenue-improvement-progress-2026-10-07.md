# LockTodoNote 수익 개선 수정 현황

작성일 2026년 10월 7일

기준 문서는 [수익 극대화 개선 보고서](/Users/nam/projects/ios/locktodonote/docs/revenue-maximization-report-2026-10-07.md)다. 보고서의 첫 출시 작업과 신규 Pro 기능 중 여러 구성 저장을 코드에 반영했다. 광고는 사용자 요청에 따라 **공식 iOS 테스트 ID만 사용**하며 Release에서는 비활성화했다. 실제 매출 증가나 출시 검증이 완료된 상태는 아니다.

## 1 코드에 적용한 변경

| 항목 | 수정 내용 | 상태 |
|---|---|---|
| 배너 광고 | 주 앱에 Google Mobile Ads와 UMP 의존성, Today 하단 배너 한 자리 | 코드 적용 |
| 무료 광고 대상 | 구매 권한 확인 완료, 첫 활성화 후 다음 앱 세션, 동의상 요청 가능할 때 | 코드 적용 |
| 입력 방해 방지 | 키보드·편집·사진 처리·결제 화면·오류 안내·백그라운드에서 배너 제외 | 코드 적용 |
| 배너 가시성 | 화면에 들어온 광고 자리에서만 로드, 실패 시 큰 빈 공간을 만들지 않음 | 코드 적용 |
| Pro 광고 제거 | 월간·연간·평생 및 구독 체험의 Pro 권한에 따라 배너 제거 | 코드 적용 |
| 동의 흐름 | UMP 갱신과 필요한 양식, 개인정보 선택 재진입 | 코드 적용 |
| ATT | 광고 없는 출시 빌드의 기존 무조건 요청 제거, 테스트 광고용 요청 추가하지 않음 | 코드 적용 |
| 광고 데이터 | 요청·로드·실패·관측 노출·테스트 수익 기록, `ad_is_test=1` | 코드 적용 |
| 첫 성공 판매 | 즉시 Paywall 대신 Today의 선택형 Pro 안내 | 코드 적용 |
| 판매 빈도 | Paywall 또는 첫 안내를 닫으면 자동 안내 7일 보류, 직접 유료 기능 선택은 허용 | 코드 적용 |
| 목적별 Paywall | 사진·D Day·단축어·테마·구성 저장에 따라 제목과 주 혜택 변경 | 코드 적용 |
| 상품 선택 | 연간·월간 우선, 평생은 접힌 더 보기, 연간 호환 ID 중 하나만 판매 화면에 표시 | 코드 적용 |
| 체험 표시 | 연간과 월간 체험 모두 종료 후 가격 표시 가능 | 코드 적용 |
| 구매 후 표시 | 구매와 구성 저장 성공을 Live Activity 시작 실패와 구분, 재시도용 draft 보존 | 코드 적용 |
| 표시 실패 측정 | `pro_display_result`로 표시 결과 별도 기록 | 코드 적용 |
| 체험 매출 혼동 | 구독 퍼널의 체험 `value=0`, 정가는 `price/quoted_price`, 실제 수익 이벤트 아님을 표시 | 코드 적용 |
| 여러 구성 저장 | 설정에 저장 목록·현재 구성 저장·전환·덮어쓰기·삭제 제공 | 코드 적용 |
| 무료와 Pro 경계 | 무료 저장 1개, Pro 여러 개, 만료 뒤 추가 구성 적용·덮어쓰기 제한 | 코드 적용 |
| 사진 보존 | 구성용 사진과 활성 화면용 사진을 독립 복사하여 변경·삭제 간 영향 방지 | 코드 적용 |
| 데이터 보존 | 구성 파일 atomic 저장, 읽기 실패 시 빈 목록으로 덮어쓰지 않음 | 코드 적용 |

기본 할 일·메모·위젯·기본 반복·기본 알림·글자 설정·내용 숨김의 무료 권한과 기존 결제 상품 ID는 유지했다. 여러 구성은 한 활성 잠금화면의 설정을 수동으로 전환하며, 콘텐츠 자체를 복제하지 않는다. 구성 이름과 기록 내용은 분석 이벤트에 전송하지 않는다.

## 2 테스트 광고 설정

- iOS App ID: `ca-app-pub-3940256099942544~1458002511`
- 적응형 배너 광고 단위: `ca-app-pub-3940256099942544/2435281174`
- Debug에서만 광고 허용. UI 테스트 실행 인자 또는 `-disable-test-ads`가 있으면 비활성화.
- 광고 요청은 비개인화 옵션으로 구성하고 publisher first party ID를 비활성화.
- 광고 수익 콜백은 `ad_test_revenue`에 기록. 실제 결제·광고 매출로 합산하지 않음.
- 광고 노출 관측 커스텀 이벤트는 `ad_impression_observed`. SDK 자동 이벤트 `ad_impression`을 중복 발신하지 않음.

설정은 [공식 배너 예제](https://developers.google.com/admob/ios/banner)와 [공식 UMP 가이드](https://developers.google.com/admob/ios/privacy)를 기준으로 작성했다. 테스트 광고도 동의 상태상 요청 가능할 때만 로드한다.

## 3 아직 적용하지 않은 후속 단계

| 작업 | 현재 상태와 적용 조건 |
|---|---|
| 실제 광고 수익화 | 실제 App ID·광고 단위 ID, AdMob 메시지·준비 상태·app ads txt·공개 개인정보 설정 후 Release 활성화 필요 |
| 보상 광고 | 보고서 순서에 따라 배너 운영과 Pro 전환을 관측한 뒤 도입. SDK 보상 획득 콜백과 제한 권한을 별도로 구현해야 함 |
| 전면 및 앱 오픈 광고 | 초기 도입하지 않음 |
| 가격 인상 | 현재 StoreKit 가격 유지. 9,900원과 14,900원은 실험 후보이며 App Store Connect 변경 및 관측 필요 |
| 기존 구매자 가격 보존 | App Store Connect에서 기존 구독자의 가격 정책 확인 필요 |
| Apple 미리알림 연동 | 권한·목록 접근·완료 동기화와 충돌 처리 개발 필요 |
| iCloud 동기화 | CloudKit 및 다중 기기 충돌·삭제·오프라인 정책 개발 필요 |
| 고급 반복과 주간 분석 | 기존 기본 기능은 유지, 새 기능은 후속 개발 |
| 스토어 설명과 스크린샷 | 실제 배포 기능에 맞춰 별도 스토어 업데이트 필요 |
| 실험군과 대조군 운영 | 현재 테스트 광고 연결 단계. 실제 광고 운영 시 코호트 배정과 중단 기준 적용 필요 |

현재 `project.yml`의 버전은 여전히 1.1.4와 build 14다. 공개 1.1.7과의 배포 코드 대응, 다음 버전 및 이미 업로드한 build 번호는 출시 전에 App Store Connect와 맞춰야 한다. 공개 상품 가격이나 배포 상태를 로컬 코드 변경만으로 수정했다고 간주하지 않는다.

## 4 변경 파일

- 광고 정책과 동의: [AdPolicy.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Ads/AdPolicy.swift), [AdService.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Ads/AdService.swift)
- 배너 UI: [AdaptiveBannerView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Ads/AdaptiveBannerView.swift)
- 구성 저장과 화면: [LayoutProfileStore.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Storage/LayoutProfileStore.swift), [LayoutProfilesView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Templates/LayoutProfilesView.swift)
- 앱 연결과 표시 결과: [AppEnvironment.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/App/AppEnvironment.swift), [RootView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/App/RootView.swift), [LockTodoNoteApp.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/App/LockTodoNoteApp.swift)
- 구매 권한과 안내: [PurchaseService.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Purchases/PurchaseService.swift), [MonetizationTriggers.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Purchases/MonetizationTriggers.swift), [PaywallView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Paywall/PaywallView.swift)
- 홈과 설정: [LockScreenTabView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Home/LockScreenTabView.swift), [SettingsTabView.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Features/Settings/SettingsTabView.swift)
- 분석과 공유 모델: [AnalyticsService.swift](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift), [LockScreenSettings.swift](/Users/nam/projects/ios/locktodonote/Packages/LockTodoNoteShared/Sources/LockTodoNoteShared/Dashboard/LockScreenSettings.swift)
- 빌드 및 개인정보: [project.yml](/Users/nam/projects/ios/locktodonote/project.yml), [Info.plist](/Users/nam/projects/ios/locktodonote/LockTodoNote/Info.plist), [PrivacyInfo.xcprivacy](/Users/nam/projects/ios/locktodonote/LockTodoNote/Resources/PrivacyInfo.xcprivacy)

## 5 검증 범위

변경 Swift 15개 파일의 구문 검사, plist 읽기, diff 공백 검사가 통과했다. XcodeGen으로 `project.yml`을 반영하여 `LockTodoNote.xcodeproj`도 재생성했다. 검증 도구의 초기 YAML 모듈 오류는 추가 설치 없이 기본 라이브러리로 처리했으며 앱 테스트 실패는 아니었다.

긴 빌드·설치·반복 테스트는 실행하지 않았다. SDK를 포함한 전체 컴파일, 광고 수신, 실제 구매·복원, 실기기 화면은 **아직 검증하지 않았다**. 현재 상태는 코드 반영 완료이며 출시 검증 완료가 아니다.

테스트 배너를 확인하려면 Debug에서 무료 사용자로 콘텐츠를 저장하고 잠금화면 또는 위젯 활성화를 완료한 다음, 앱을 백그라운드로 보냈다가 다시 열고 Today 하단으로 이동한다. 키보드와 다른 안내를 닫고 UMP의 요청 가능 상태가 되어야 한다. Pro 사용자와 Release에서는 배너가 나오지 않는 것이 정상이다.
