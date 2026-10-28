# 오프닝 광고 시뮬레이터 테스트 — 2026-10-27

## 결과

일반 무료 사용자 광고 표시와 Pro 미노출 테스트는 통과했다. 다만 저장된 Pro 상태가 무료로 변경되는 첫 실행에는 광고 기회를 건너뛰는 경계 사례가 확인되어, 모든 무료 사용자 실행에서 미노출 문제가 없다고 판정할 수는 없다. 앱 소스는 수정하지 않았다.

## 환경 및 실행

- iOS 26.1 / LockTodoNote Settings QA 시뮬레이터
- 현재 작업 디렉터리의 Debug 소스로 빌드
- Google 공식 App Open 테스트 광고 ID 사용
- 무료/Pro 판정은 기존 `-device-qa -qa-entitlement free|pro` 기능으로 설정했다. 실제 StoreKit 구매·만료 검증은 포함하지 않았다.
- 실행: `xcodebuild -project LockTodoNote.xcodeproj -scheme LockTodoNote -configuration Debug -destination 'platform=iOS Simulator,id=BA32E88F-D450-4FE5-A01D-4FEDC5FF79A8' -only-testing:LockTodoNoteUITests/DeviceFeatureUITests/test09AdMobTestAppOpenAndProSuppression -parallel-testing-enabled NO -resultBundlePath docs/app-open-ad-qa-2026-10-27/app-open.xcresult test`
- UI 테스트 1건 통과, 실패 0건, 17.684초.

## 확인 항목

| 항목 | 결과 | 근거 |
|---|---|---|
| 무료 사용자 콜드 런치 | 통과 | `eligible=true`, `ad_impression_observed`, 실제 광고 화면 첨부 |
| Pro 사용자 콜드 런치 | 통과 | `eligible=false`, 광고 요청 이벤트 없음, 앱 화면 첨부 |
| 무료 사용자 백그라운드 복귀 | 통과 | 수동 재진입 후 공식 테스트 광고 화면 확인 |
| 광고 닫기 및 앱 조작 | 통과 | Continue to app 후 설정 화면 이동 성공 |
| 광고 닫은 직후 재진입 | 통과 | 광고 없이 설정 화면 유지, 다음 광고 `ad_loaded` 상태 |
| 다른 광고 형식 제거 | 코드 확인 | 앱 소스의 BannerView/InterstitialAd/RewardedAd/NativeAd 사용 없음, 광고 로드는 AppOpenAd만 존재 |

## 발견된 경계 사례

1. Pro QA 실행으로 Pro 캐시를 저장한다.
2. 데이터 초기화 없이 `-device-qa -device-qa-ads -qa-entitlement free`로 프로세스를 다시 실행한다.
3. 무료 판정(`eligible=true`)에도 첫 실행 광고는 표시되지 않았다. 당시 진단은 `ready=false event=none`이었다(`manual-free.png`).
4. 홈으로 나갔다가 같은 프로세스로 복귀하면 광고가 표시됐다(`free-foreground-ad.png`). 광고 종료 후 다음 광고도 로드됐다.

코드상 `AdService.beginAppOpenIfDue()`는 캐시된 `isPro` 때문에 광고 대상이 아니면 `isAppOpenPending`을 해제한다. 이후 `updateEntitlement`에서 무료로 바뀌어도 소진한 실행 기회를 다시 시작하지 않는다. 실제 구독 만료 전환에서도 같은 순서가 발생할 가능성이 있으나, 실제 StoreKit 만료로 재현한 결과는 아니다. 늦은 광고가 앱 조작을 덮지 않도록 하는 기존 정책과 함께 수정 방향을 정해야 한다.

## 증거 및 한계

- 자동 테스트 원본: `app-open.xcresult`, `xcodebuild.log`
- 자동 테스트 화면: `attachments/manifest.json`과 PNG 2개
- 수동 화면: `manual-free.png`, `free-foreground-ad.png`, `free-cooldown-no-ad.png`
- 테스트 광고의 SDK 로드·표시만 검증했다. Release 운영 광고 ID의 실제 송출, AdMob 계정·재고 상태, 지역별 UMP 동의 화면, 오프라인, 2분 경과 후 재노출 및 iPad는 이번 실행 범위에 포함하지 않았다.
