# 이벤트 목록과 발생 계약

2026-10-30 · `L1.2.2` · 아래 수집 상태는 코드/로컬 테스트 기준이다. Firebase 서버의 실제 수신을 확인한 목록이 아니다.

## 정확한 발생 조건

| 이벤트 | 발생 조건·해석 |
| --- | --- |
| `onboarding_start`, `onboarding_step_view`, `onboarding_complete` | 기존 온보딩 표시/단계 진입/사용자 종료 콜백. 완료와 저장·표시 시작을 합산하지 않음 |
| `quick_add_invoked`, `quick_add_type_selected`, `quick_capture_focused` | 기존 진입/유형 선택/포커스 콜백. 포커스는 저장 성공이 아님 |
| `todo_created`, `first_todo_created`, `memo_created` | 앱의 저장 성공 뒤. first_todo_created는 설치 상태 기준 1회인 보조 이벤트로 todo_created와 합산하지 않음 |
| `l122_capture` | source별 최초 포커스/작성 시트 표시에서 started, 해당 세션의 저장 성공/실패/명시 취소/화면 이탈/유형 변경에서 saved/failed/cancelled/interrupted/type_changed. capture_id로 연결. 반복 포커스는 중복 시작하지 않음 |
| `l122_memo_display` | 오늘에서 메모 저장 성공 후. 선택 여부·규칙 제한·기존 메모 교체·저장 전후 표시 설정 동일 여부. 메모 본문은 없음. 시작은 첫 글자 입력을 의미하지 않음 |
| `l122_content_mutation` | CardStore 저장 성공 후 수정·삭제·완료 취소. completion_context는 기존 todo_completed의 반복/미리알림 맥락이며 또 하나의 완료가 아님. repeat_created는 반복 신규 저장의 보조 분류 |
| `todo_completed` | 앱 UI에서는 저장 성공 후, 외부에서는 pending_saved 후 원본 시각으로 큐에 기록. 외부의 최종 파일 저장과 구분. 취소는 이 이벤트가 아님 |
| `l122_external_commit` | 앱이 확장 작업을 카드 파일에 병합한 뒤 기록. 완료는 실제 완료 항목 존재 여부에 success/unresolved, 추가도 생성 대상 존재 여부에 success/unresolved. 같은 원본 완료 event_id로 연결하고 todo_completed를 재발신하지 않음 |
| `l122_first_completion` | 앱 저장 완료 또는 외부 card_file success 관측 후 설치 상태 기준 1회. 가장 먼저 관측한 완료이며 지연 이벤트가 더 오래됐어도 재작성하지 않음 |
| `live_activity_start_attempt/success/failed` | 실제 요청 직전/요청 성공/실패. request_id로 연결. 자동 복구는 수동 사용과 분리 |
| `activation_complete` | 기존 content_and_setup_v2 유지. time_to_value_seconds는 기존 ‘첫 콘텐츠 저장까지’ 의미가 남으므로 표시 완료 시간으로 쓰지 않음 |
| `l122_first_value` | activation_complete의 1회 발신과 함께 content_and_setup 등록 도달까지 elapsed_seconds 기록. 실제 잠금화면 시청/읽기 증거가 아님 |
| `l122_display_overflow` | Dashboard 발행 시 후보 구간·코드상 행 상한·선택 범위 상태가 바뀔 때만. measurement=render_code_upper_bound. 개인정보 모드에서는 후보 unknown/overflow 생략. 실제 표시·물리적 글자 수용량이나 중요도 추정이 아님 |
| `l122_display_selection` | 자동 전환 규칙 저장 성공 후 전체/선택 및 선택 개수 구간. 편집 화면을 열거나 취소한 것과 구분 |
| `l122_new_item_scope` | 앱의 새 할 일 저장 성공 후 현 규칙 범위에 포함된 개수 구간. 날짜·템플릿·공간까지 통과한 실제 노출을 의미하지 않음 |
| `l122_feature_action` | 자동 전환 화면 진입·저장·활성/비활성·실패·명시 취소, 빈 구성 저장 바로가기 진입/성공, 고급 반복 편집 진입/적용/해제, 미리알림 연결 시도/성공/실패/해제. feature/result enum으로 구분 |
| `l122_reminder_import` | 기존 자동 동기화의 저장 성공 뒤 가져온 개수 구간이 달라질 때. source=automatic_sync, 직접 사용자 사용으로 계산 금지 |
| `l122_queue_health` | 큐 상한으로 폐기된 누적 값이 직전 보고보다 증가했을 때 다음 앱 flush에서 delta 보고 |
| `app_returned` | 기존 설치 다음 날 이후 하루 1회 실제 foreground. 모든 세션이나 D1 자체가 아님 |
| `widget_timeline_requested`, `lockscreen_activity_updated` | OS/기술 진단. 이번 버전부터 각각 최대 시간당 1회 큐 기록. 사람의 조회·활성으로 사용 금지 |
| `widget_configuration_checked/configured_detected`, `widget_installed_confirmed` | OS 구성 확인/구성 변화/확인 방식 구분. 실제 위젯 시청을 의미하지 않음 |
| `pro_template_tapped`, `pro_info_sheet_viewed`, `pro_preview_viewed/interacted` | 기존 선택/시트/미리보기 표시/조작 콜백을 유지. 네 이벤트를 합산한 사람 수로 쓰지 않음 |
| `paywall_seen`, `plan_selected`, `purchase_started/completed/cancelled/failed/pending`, `purchase_value_applied`, `paywall_dismissed`, `restore_completed` | 기존 표시·상품 선택(기본값 구분)·StoreKit 결과·기능 적용·닫기·복원 결과. quoted price는 매출이 아니며 transaction_environment가 unknown이면 Production으로 분류 금지 |
| `l122_purchase_application` | 검증 권리 처리 후 목적 적용의 success/failed/display_recovery_needed/not_requested. 목적 없음은 성공으로 세지 않음 |
| `ad_*` | 기존 요청·로드·노출·오류·실수익 SDK 콜백 유지. 앱 오픈 정책이 false라 실제 요청/노출은 기대하지 않음. ad_test_revenue와 ad_paid_revenue 분리 |

## 전체 발신 지점

아래 목록은 모든 고정 이름 발신 지점이다. 동적 `layout_profile_<action>`은 saved/applied/deleted 등의 기존 호출 값, `adEvent(name)`는 AdService의 기존 상수를 따른다. 이름의 슬래시 표기는 위 표에서만 축약했으며 실제 발신은 아래와 같다.

| 이벤트 | 발신 함수 | 코드 |
| --- | --- | --- |
| `activation_complete` | `tryCompleteActivation` | [AnalyticsService.swift:945](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:945) |
| `ad_consent_failed` | `prepareIfNeeded` | [AdService.swift:308](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Ads/AdService.swift:308) |
| `ad_consent_failed` | `prepareIfNeeded` | [AdService.swift:328](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Ads/AdService.swift:328) |
| `app_returned` | `appReturned` | [AnalyticsService.swift:827](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:827) |
| `card_save_failed` | `cardSaveFailed` | [AnalyticsService.swift:805](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:805) |
| `dday_set` | `ddaySet` | [AnalyticsService.swift:448](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:448) |
| `display_mode_selected` | `displayModeSelected` | [AnalyticsService.swift:469](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:469) |
| `first_todo_created` | `todoCreated` | [AnalyticsService.swift:344](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:344) |
| `l122_capture` | `captureStarted` | [AnalyticsService.swift:115](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:115) |
| `l122_capture` | `captureEnded` | [AnalyticsService.swift:122](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:122) |
| `l122_content_mutation` | `contentMutation` | [AnalyticsService.swift:133](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:133) |
| `l122_display_overflow` | `displayCandidates` | [AnalyticsService.swift:148](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:148) |
| `l122_display_selection` | `displaySelection` | [AnalyticsService.swift:166](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:166) |
| `l122_external_commit` | `load` | [CardRepository.swift:63](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Storage/CardRepository.swift:63) |
| `l122_external_commit` | `load` | [CardRepository.swift:73](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Storage/CardRepository.swift:73) |
| `l122_feature_action` | `feature` | [AnalyticsService.swift:102](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:102) |
| `l122_first_completion` | `recordFirstCompletion` | [AnalyticsService.swift:877](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:877) |
| `l122_first_value` | `tryCompleteActivation` | [AnalyticsService.swift:963](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:963) |
| `l122_memo_display` | `memoCaptureDisplayed` | [AnalyticsService.swift:127](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:127) |
| `l122_new_item_scope` | `newTodoScope` | [AnalyticsService.swift:160](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:160) |
| `l122_purchase_application` | `purchaseApplication` | [AnalyticsService.swift:570](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:570) |
| `l122_queue_health` | `flushQueuedEvents` | [AnalyticsService.swift:892](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:892) |
| `l122_reminder_import` | `reminderImport` | [AnalyticsService.swift:156](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:156) |
| `live_activity_became_stale` | `liveActivityBecameStale` | [AnalyticsService.swift:501](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:501) |
| `live_activity_restarted` | `restartActivity` | [GlanceCardAppIntents.swift:707](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:707) |
| `live_activity_restarted` | `liveActivityRestarted` | [AnalyticsService.swift:497](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:497) |
| `live_activity_start_attempt` | `restartActivity` | [GlanceCardAppIntents.swift:670](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:670) |
| `live_activity_start_attempt` | `liveActivityStartAttempt` | [AnalyticsService.swift:381](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:381) |
| `live_activity_start_failed` | `perform` | [GlanceCardAppIntents.swift:284](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:284) |
| `live_activity_start_failed` | `liveActivityStartFailed` | [AnalyticsService.swift:427](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:427) |
| `live_activity_start_success` | `restartActivity` | [GlanceCardAppIntents.swift:701](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:701) |
| `live_activity_start_success` | `liveActivityStarted` | [AnalyticsService.swift:412](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:412) |
| `lock_screen_template_changed` | `templateChanged` | [AnalyticsService.swift:445](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:445) |
| `lockscreen_activity_ended` | `liveActivityEnded` | [AnalyticsService.swift:441](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:441) |
| `lockscreen_activity_updated` | `refreshActivities` | [GlanceCardAppIntents.swift:654](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:654) |
| `lockscreen_activity_updated` | `restartActivity` | [GlanceCardAppIntents.swift:695](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:695) |
| `lockscreen_interacted` | `perform` | [GlanceCardAppIntents.swift:425](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:425) |
| `lockscreen_interacted` | `perform` | [GlanceCardAppIntents.swift:455](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:455) |
| `lockscreen_interacted` | `lockscreenInteracted` | [AnalyticsService.swift:811](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:811) |
| `lockscreen_preview_seen` | `lockscreenPreviewSeen` | [AnalyticsService.swift:306](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:306) |
| `memo_created` | `memoCreated` | [AnalyticsService.swift:488](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:488) |
| `migration_completed` | `record` | [AnalyticsService.swift:864](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:864) |
| `migration_failed` | `record` | [AnalyticsService.swift:866](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:866) |
| `multiline_todo_imported` | `multilineTodoImported` | [AnalyticsService.swift:478](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:478) |
| `onboarding_complete` | `onboardingComplete` | [AnalyticsService.swift:210](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:210) |
| `onboarding_start` | `onboardingStart` | [AnalyticsService.swift:202](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:202) |
| `onboarding_step_view` | `onboardingStepViewed` | [AnalyticsService.swift:206](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:206) |
| `paywall_dismissed` | `paywallDismissed` | [AnalyticsService.swift:630](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:630) |
| `paywall_seen` | `paywallSeen` | [AnalyticsService.swift:583](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:583) |
| `plan_selected` | `planSelected` | [AnalyticsService.swift:624](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:624) |
| `pro_display_result` | `proDisplayResult` | [AnalyticsService.swift:574](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:574) |
| `pro_info_sheet_viewed` | `proInfoSheetViewed` | [AnalyticsService.swift:595](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:595) |
| `pro_preview_interacted` | `proPreviewInteracted` | [AnalyticsService.swift:603](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:603) |
| `pro_preview_viewed` | `proPreviewViewed` | [AnalyticsService.swift:599](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:599) |
| `pro_template_tapped` | `proTemplateTapped` | [AnalyticsService.swift:591](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:591) |
| `purchase_cancelled` | `purchaseCancelled` | [AnalyticsService.swift:768](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:768) |
| `purchase_completed` | `purchaseCompleted` | [AnalyticsService.swift:682](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:682) |
| `purchase_failed` | `purchaseFailed` | [AnalyticsService.swift:785](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:785) |
| `purchase_pending` | `purchasePending` | [AnalyticsService.swift:691](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:691) |
| `purchase_started` | `purchaseStarted` | [AnalyticsService.swift:661](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:661) |
| `purchase_value_applied` | `purchaseValueApplied` | [AnalyticsService.swift:712](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:712) |
| `quick_add_education_completed` | `perform` | [GlanceCardAppIntents.swift:222](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:222) |
| `quick_add_education_completed` | `quickAddEducationCompleted` | [AnalyticsService.swift:298](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:298) |
| `quick_add_failed` | `perform` | [GlanceCardAppIntents.swift:78](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:78) |
| `quick_add_failed` | `perform` | [GlanceCardAppIntents.swift:134](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:134) |
| `quick_add_failed` | `perform` | [GlanceCardAppIntents.swift:158](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:158) |
| `quick_add_failed` | `perform` | [GlanceCardAppIntents.swift:195](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:195) |
| `quick_add_failed` | `quickAddFailed` | [AnalyticsService.swift:253](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:253) |
| `quick_add_invoked` | `perform` | [GlanceCardAppIntents.swift:88](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:88) |
| `quick_add_invoked` | `quickAddInvoked` | [AnalyticsService.swift:216](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:216) |
| `quick_add_limit_reached` | `perform` | [GlanceCardAppIntents.swift:71](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:71) |
| `quick_add_limit_reached` | `quickAddLimitReached` | [AnalyticsService.swift:261](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:261) |
| `quick_add_onboarding_cta` | `quickAddOnboardingCTA` | [AnalyticsService.swift:276](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:276) |
| `quick_add_onboarding_seen` | `quickAddOnboardingSeen` | [AnalyticsService.swift:269](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:269) |
| `quick_add_tip_seen` | `quickAddTipSeen` | [AnalyticsService.swift:283](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:283) |
| `quick_add_tip_tapped` | `quickAddTipTapped` | [AnalyticsService.swift:290](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:290) |
| `quick_add_type_selected` | `perform` | [GlanceCardAppIntents.swift:115](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:115) |
| `quick_add_type_selected` | `quickAddTypeSelected` | [AnalyticsService.swift:225](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:225) |
| `quick_capture_focused` | `quickCaptureFocused` | [AnalyticsService.swift:474](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:474) |
| `reminder_action` | `reminderAction` | [AnalyticsService.swift:798](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:798) |
| `restore_completed` | `restoreCompleted` | [AnalyticsService.swift:794](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:794) |
| `review_eligibility_reached` | `reviewEligibilityReached` | [AnalyticsService.swift:839](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:839) |
| `review_prompt_deferred` | `reviewPromptDeferred` | [AnalyticsService.swift:847](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:847) |
| `review_prompt_requested` | `reviewPromptRequested` | [AnalyticsService.swift:843](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:843) |
| `review_request_skipped` | `reviewRequestSkipped` | [AnalyticsService.swift:855](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:855) |
| `review_store_link_opened` | `reviewStoreLinkOpened` | [AnalyticsService.swift:851](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:851) |
| `settings_opened` | `settingsOpened` | [AnalyticsService.swift:465](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:465) |
| `shortcut_quick_add` | `perform` | [GlanceCardAppIntents.swift:204](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:204) |
| `shortcut_quick_add` | `shortcutQuickAdd` | [AnalyticsService.swift:239](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:239) |
| `temporary_pro_trial_started` | `temporaryTrialStarted` | [AnalyticsService.swift:835](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:835) |
| `todo_completed` | `perform` | [GlanceCardAppIntents.swift:397](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardAppIntents.swift:397) |
| `todo_completed` | `todoCompleted` | [AnalyticsService.swift:376](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:376) |
| `todo_created` | `todoCreated` | [AnalyticsService.swift:328](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:328) |
| `top_destination_selected` | `topDestinationSelected` | [AnalyticsService.swift:459](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:459) |
| `trial_cta_tapped` | `trialCTATapped` | [AnalyticsService.swift:638](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:638) |
| `widget_configuration_check_failed` | `widgetConfigurationCheckFailed` | [AnalyticsService.swift:528](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:528) |
| `widget_configuration_checked` | `widgetConfigurationsChecked` | [AnalyticsService.swift:521](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:521) |
| `widget_configured_detected` | `widgetConfigurationsChecked` | [AnalyticsService.swift:523](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:523) |
| `widget_installed_confirmed` | `widgetInstalledConfirmed` | [AnalyticsService.swift:532](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:532) |
| `widget_setup_guide_viewed` | `widgetSetupStarted` | [AnalyticsService.swift:505](/Users/nam/projects/ios/locktodonote/LockTodoNote/Core/Analytics/AnalyticsService.swift:505) |
| `widget_timeline_requested` | `getTimeline` | [GlanceCardLockScreenWidget.swift:76](/Users/nam/projects/ios/locktodonote/Extensions/WidgetExtension/GlanceCardLockScreenWidget.swift:76) |

## 기존 계측 조사 분류

- **코드 연결 및 로컬 검증:** 작성 저장, 앱/외부 완료, 온보딩, 활동 요청, 구매 퍼널, 광고 콜백. 실제 iPad DebugView에서 widget_configuration_checked 및 릴리스 공통 속성을 확인했다. 그 외 개별 경로의 전수 수신/중복 검증은 미완료다.
- **정보 부족 보완:** 릴리스/정확한 앱 버전, 확장 원본 버전·전송 시각, 작성 결과/시간 구간, 수정·삭제·취소, 표시 초과/범위, 반복/연결 맥락.
- **시점·중복 위험 보완:** 확장 pending 저장과 최종 카드 저장 분리, 이미 빠진 완료 버튼의 재실행 차단, 직접 완료를 병합 때 중복 발신하지 않음.
- **기술 동작 오집계 방지:** 위젯 timeline·activity_updated 시간당 제한, 후보 계산/자동 가져오기에는 직접 사용자 활동 의미를 부여하지 않음.
- **관측 불가/아직 부족:** 눈으로 읽기, 앱을 열지 않아 영구 미전송된 행동, 모든 작성 표면의 명시 취소·강제 종료 원인, 초 단위 시간 경계 실행, 실제 거래 매출·갱신, 자동 전환의 구매 후 목적 기능 적용 연결은 UI 로그만으로 완전하지 않다.

## 2026-10-31 추가 계약

- `l122_release_observed`: 로컬 설치 기록 기준 릴리스당 1회. cohort는 new_observed 또는 existing_or_unknown. SDK first_open 재발생을 신규 설치로 오인하지 않도록 분석 시 함께 사용한다.
- 구매 완료의 transaction_trial_state/trial_basis는 검증 거래의 offer 증거로만 확정한다. 화면의 체험 가능 여부는 quoted_context이며 실제 체험 시작·수익이 아니다.
