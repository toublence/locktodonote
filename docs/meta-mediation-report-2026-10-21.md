# Meta 미디에이션 추가 및 iPad 검증

## 적용 내용

- `project.yml`에 Google 공식 Meta 어댑터 6.22.0.0과 Meta Audience Network SDK 6.22.0을 추가했다. 어댑터는 공식 저장소의 고정 revision을 사용한다. 본앱에만 연결하며 위젯·공유 확장에는 넣지 않았다.
- 기존 운영 배너 광고 단위와 UMP 동의 흐름을 유지한다. Meta 개인정보 설정을 SDK 초기화 전과 배너 요청 전에 갱신한다. iOS 17 이상은 Meta SDK가 OS ATT 상태를 읽고, iOS 16에서는 실제 ATT 허용 여부만 전달한다. 추가 ATT 허용 요청이나 강제 허용은 없다.
- Meta LDU는 국가·주를 Meta가 판별하도록 보수적으로 적용했다. 미국 해당 지역에서는 허용된 경우에도 맞춤 광고 범위를 제한할 수 있다. AdMob의 Additional Consent 파트너 설정을 대체하지 않는다.
- Meta 배너에 필요한 rootViewController를 명시했다. 기존 Info.plist에는 Meta SKAdNetwork ID 2개가 이미 포함돼 있다.
- 본앱·확장의 build 번호를 18로 통일했다.
- Debug 전용 Meta QA 화면과 실기기 테스트를 추가했다. 일반 Debug는 Google 공식 테스트 광고를 사용하고, 명시적인 Meta QA에서만 운영 광고 단위에 테스트 기기를 등록한다. Ad Inspector가 정상 종료된 후에만 QA 배너를 요청할 수 있다. 테스트 기기·Meta 테스트 모드·QA 화면은 Release에 포함되지 않는다.

## 실제 확인한 결과

기기: iPad Air 11인치 M2, iPadOS 26.6.2. 앱 1.1.8 build 18, 개발 서명 Debug.

| 항목 | 결과 |
|---|---|
| Debug 실기기 빌드·설치 | 성공 |
| Release 빌드 | 성공. 코드 서명 없는 generic iOS 빌드이며 배포·Archive 검증은 아님 |
| Release 구성 | MetaAdapter·FBAudienceNetwork 포함, QA 화면 제외, 본앱·확장 build 18 일치 |
| Meta 어댑터 초기화 | `GADMediationAdapterFacebook`, `Ready` |
| UMP·ATT | `canRequestAds=true`, 기기의 기존 ATT 상태 `authorized` 확인. 권한 자동 승인 없음 |
| Meta 테스트 기기 등록 | SDK 공개 API의 `isTestMode()=true` |
| Google 테스트 기기 등록 | Ad Inspector 실제 열림으로 확인 |
| 단일 소스 선택 | `Meta Audience Network (Bidding)` 선택 후 테스트 시작 |
| 운영 광고 단위의 테스트 요청 | `ad_failed:1` / No fill. loaded adapter는 null, mediation line items는 비어 있음 |
| Ad Inspector 직접 테스트 요청 | Meta 단일 소스가 켜진 상태에서 같은 광고 단위의 `Request test ad` 실행. `No Fill`, `Request Error: No ad to show.` 반환 |
| Meta 실제 광고 노출 | 미확인. Google 테스트 광고 노출이나 어댑터 Ready를 Meta 광고 성공으로 간주하지 않음 |
| 기존 분석 계약 테스트 | Meta 포함 빌드에서 17개 통과 |
| 테스트 소스 강제 해제 | `Stop test` 확인 후 `Inactive`와 `Test stopped`를 실제 화면에서 확인 |
| 데이터 복원 | 기존 카드 5개의 ID·내용·완료 상태 보존. QA 권한을 복원하고 QA 인자 없는 일반 앱으로 재실행 |

광고 응답의 mediation group은 `락투두 - 배너`였다. 광고 요청이 서버에 도달했으나 Meta 광고를 받지 못했다. 빈 입찰 응답만으로 콘솔 설정 오류나 SDK 오류를 단정할 수 없다. 사용자가 완료했다고 한 AdMob 설정은 변경하지 않았다.

동일 iPad에서 Steady의 Meta 전면 광고 로드·노출·닫기와 Ad Inspector 배너 Fill이 성공한 기존 기록을 확인했다. 따라서 Facebook 앱 설치·로그인 부재를 이번 No fill의 원인이나 진행 차단 조건으로 판단하지 않는다. 앞서 설치·로그인을 요청한 것은 이번 기기의 실제 성공 기록을 확인하지 못한 채 문서의 일반 요건을 적용한 오류였다. 해당 요청은 철회했다.

Steady와 같은 Ad Inspector 직접 요청 방식에서도 LockTodoNote 광고 단위 `8606002846`은 No fill이었다. 앱의 SwiftUI 배너 표시 경로를 거치지 않은 요청에서도 재현됐다는 증거이며, 서버가 제공하지 않은 광고를 앱 코드에서 강제 노출할 수는 없다. 현재 증거만으로 원인이 입찰 수요·서버 설정 반영·매핑 중 무엇인지는 구분할 수 없다. Meta 연동과 실기기 진단은 수행했으나 실제 Meta 로드·노출 성공 조건은 충족하지 못했다.

## 증거와 제한

- `meta-mediation-qa-2026-10-21/build.log`: Debug 테스트 빌드 성공.
- `meta-mediation-qa-2026-10-21/inspector.log`: iPad 어댑터 Ready 및 Ad Inspector 열기 테스트 통과.
- `meta-mediation-qa-2026-10-21/single-source.log`: Meta 단일 광고 소스 선택 확인.
- `meta-mediation-qa-2026-10-21/banner.log`: 분석 계약 테스트 17개 통과와 Meta 요청의 No fill 응답. UI 테스트는 단일 소스 해제 확인 대화상자 처리 누락으로 실패했으며 후속 코드에서 수정했다.
- `meta-mediation-qa-2026-10-21/details.log`: 후속 테스트 러너 통신 오류. 앱 광고 동작의 성공·실패 증거로 사용하지 않는다.
- `meta-mediation-qa-2026-10-21/release-build.log`, `release-verification.json`: Release 빌드와 SDK 포함·QA 화면 제외·버전 일치 확인.
- `meta-mediation-qa-2026-10-21/details-retry.log`: Meta No fill 재확인. 수정한 Stop test 확인 대화상자를 처리하고 Inactive 확인 후 데이터 복원·일반 앱 재실행. 실제 Meta 노출 조건이 충족되지 않아 UI 테스트의 노출 assertion은 실패했다.
- `meta-mediation-qa-2026-10-21/inspector-no-fill-and-test-disabled.png`: 실제 Ad Inspector의 배너 No Fill, 단일 소스 Inactive, Test stopped 화면.
- `meta-mediation-qa-2026-10-21/data-preservation.json`: 기존 카드 5개 내용·완료 보존 비교. 기존 앱의 날짜 이월로 변경되는 `targetDateTime`·`updatedAt`은 앞선 리텐션 보고서와 동일하게 비교에서 제외.
- `meta-mediation-qa-2026-10-21/final-device.log`: 인앱 Meta 요청의 No fill과 해당 요청의 Inspector 오류 상세.
- `meta-mediation-qa-2026-10-21/inspector-direct.log`, `inspector-direct-no-fill.png`: Meta 단일 소스 활성 상태에서 Inspector 직접 요청도 No fill인 증거. 테스트 소스 해제와 원본 복원·일반 앱 실행 후 종료. 실제 노출 assertion은 실패로 남겨두었다.

기존 할 일 데이터는 QA 백업·복원 흐름으로 보존한다. 실제 광고 클릭·구매·콘솔 변경은 수행하지 않았다. xcresult와 원본 화면은 비공개 임시 경로에 보관한다.

공식 근거: [Google Meta iOS 미디에이션 가이드](https://developers.google.com/admob/ios/mediation/meta), [Google 공식 SPM 어댑터](https://github.com/googleads/googleads-mobile-ios-mediation-meta), [Meta 공식 SDK](https://github.com/facebook/FBAudienceNetwork).
