import XCTest

@MainActor
final class DeviceFeatureUITests: XCTestCase {
    private var restoreAfterRetentionTest = false

    func test11InstalledLockWidgetRefreshAndOpenWithoutReset() throws {
        continueAfterFailure = false
        restoreAfterRetentionTest = true
        let app = XCUIApplication()
        app.launchArguments = ["-device-qa", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 30))
        wait(app.staticTexts["qa.widget"], "lock=true", 20)
        let title = "QAWidget-\(UUID().uuidString.prefix(8))"
        app.buttons["navigation.today"].tap()
        let field = app.textFields["today.quickCapture"]
        for _ in 0..<5 where !field.isHittable { app.swipeUp() }
        field.tap(); field.typeText(title)
        app.buttons["today.quickCapture.save"].tap()
        hideKeyboard(app)
        let preview = app.staticTexts["qa.widget"]
        let ownFirst = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", title), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [ownFirst], timeout: 10), .completed)
        let expected = try XCTUnwrap(preview.value as? String)
        let stored = app.staticTexts["qa.storage"].value as? String ?? "[]"
        let cards = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [[String: Any]])
        let card = try XCTUnwrap(cards.first { $0["title"] as? String == title })
        let cardID = try XCTUnwrap(card["id"] as? String)
        let itemID = try XCTUnwrap((card["checklistItems"] as? [[String: Any]])?.first?["id"] as? String)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func showLockScreen() {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.005))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.75))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        showLockScreen()
        let widgetText = system.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        XCTAssertTrue(widgetText.waitForExistence(timeout: 40), "Saved QA item must appear in the actual system widget")
        shot("lock-widget-created-item-real-system")
        widgetText.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Tapping the real widget must open the app")
        print("RETENTION_QA: actual lock widget create/render/tap-to-open PASS")
        let toggle = app.buttons["todo.toggle.\(cardID):\(itemID)"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeDown() }
        XCTAssertTrue(toggle.isHittable); toggle.tap()
        let next = try XCTUnwrap(preview.value as? String)
        XCTAssertFalse(next.contains(title))
        XCTAssertFalse(next.isEmpty)
        showLockScreen()
        let updated = system.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", next)).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 40), "Widget must update after completing the QA item")
        XCTAssertFalse(system.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists)
        shot("lock-widget-completed-item-real-system")
        print("RETENTION_QA: actual lock widget completion refresh PASS")
        app.activate()
    }

    override func tearDown() async throws {
        await MainActor.run {
          if restoreAfterRetentionTest {
            let app = XCUIApplication()
            app.terminate()
            app.launchArguments = ["-device-qa", "-device-qa-restore"]
            app.launch()
            XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30), "Original data restore must finish")
            app.terminate()
            app.launchArguments = []
            app.launch()
          }
        }
        try await super.tearDown()
    }

    /// Runs against existing device data. No reset, seeding, or purchase occurs.
    /// DeviceQASupport archives the original data before applying QA overrides.
    func test10RetentionCRUDGuideAndAppOpenAdWithoutReset() throws {
        continueAfterFailure = false
        restoreAfterRetentionTest = true
        let app = XCUIApplication()
        func launchRetention(pro: Bool, ads: Bool = false) {
            app.launchArguments = ["-device-qa", "-qa-entitlement", pro ? "pro" : "free", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            // The app open ad would cover every launch of the CRUD steps.
            if ads { app.launchArguments.append("-device-qa-ads") }
            app.launch()
            XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30))
            if app.buttons["onboarding.skip"].exists { app.buttons["onboarding.skip"].tap() }
            if app.buttons["paywall.close"].exists { app.buttons["paywall.close"].tap() }
        }
        func storedCards() throws -> [[String: Any]] {
            let value = app.staticTexts["qa.storage"].value as? String ?? "[]"
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [[String: Any]])
        }
        func ownCard(_ title: String) throws -> [String: Any] {
            try XCTUnwrap(try storedCards().first { $0["title"] as? String == title })
        }
        func scrollTo(_ element: XCUIElement) {
            for _ in 0..<5 where !element.isHittable {
                if element.frame.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            }
            XCTAssertTrue(element.isHittable)
        }
        func capture(_ title: String) {
            let field = app.textFields["today.quickCapture"]
            scrollTo(field)
            field.tap(); field.typeText(title)
            app.buttons["today.quickCapture.save"].tap()
            hideKeyboard(app)
        }

        launchRetention(pro: false)
        app.buttons["navigation.today"].tap()
        let originalIDs = Set(try storedCards().compactMap { $0["id"] as? String })
        let title = "QA-Retention-\(UUID().uuidString.prefix(8))"
        capture(title)
        let card = try ownCard(title)
        let cardID = try XCTUnwrap(card["id"] as? String)
        let itemID = try XCTUnwrap((card["checklistItems"] as? [[String: Any]])?.first?["id"] as? String)
        let compositeID = "\(cardID):\(itemID)"
        let edit = app.buttons["todo.edit.\(compositeID)"]
        scrollTo(edit); edit.tap()
        let editor = app.textFields["todo.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("-Edited")
        app.buttons["todo.editor.save"].tap()
        let edited = try XCTUnwrap(try storedCards().first { $0["id"] as? String == cardID }?["title"] as? String)
        XCTAssertTrue(edited.contains("Edited"))
        app.terminate(); launchRetention(pro: false)
        XCTAssertNotNil(try storedCards().first { $0["id"] as? String == cardID })
        app.buttons["navigation.today"].tap()
        let delete = app.buttons["todo.delete.\(compositeID)"]
        scrollTo(delete); delete.tap()
        XCTAssertFalse(try storedCards().contains { $0["id"] as? String == cardID })

        let completionTitle = title + "-Complete"
        capture(completionTitle)
        let completionCard = try ownCard(completionTitle)
        let completionID = try XCTUnwrap(completionCard["id"] as? String)
        let completionItemID = try XCTUnwrap((completionCard["checklistItems"] as? [[String: Any]])?.first?["id"] as? String)
        let toggle = app.buttons["todo.toggle.\(completionID):\(completionItemID)"]
        scrollTo(toggle); toggle.tap()
        let completed = try ownCard(completionTitle)
        XCTAssertEqual((completed["checklistItems"] as? [[String: Any]])?.first?["isDone"] as? Bool, true)
        XCTAssertTrue(originalIDs.isSubset(of: Set(try storedCards().compactMap { $0["id"] as? String })))
        print("RETENTION_QA: create/edit/relaunch/delete/complete PASS; original IDs preserved")

        app.buttons["navigation.settings"].tap()
        let guide = app.buttons["settings.liveWidgets"]
        scrollTo(guide); guide.tap()
        XCTAssertTrue(app.buttons["widget.setup.confirm"].waitForExistence(timeout: 10))
        wait(app.staticTexts["qa.widget"], "known=true", 15)
        print("RETENTION_QA: \(app.staticTexts["qa.widget"].label)")
        shot("retention-widget-guide-ipad")
        app.terminate(); launchRetention(pro: false, ads: true)
        wait(app.staticTexts["qa.ads"], "eligible=true", 15)
        wait(app.staticTexts["qa.ads"], "ad_impression_observed", 60)
        shot("retention-official-test-app-open-ipad")
        print("RETENTION_QA: official test app open impression PASS")
        app.terminate(); launchRetention(pro: true, ads: true)
        wait(app.staticTexts["qa.ads"], "eligible=false", 15)
        XCTAssertFalse(app.staticTexts["qa.ads"].label.contains("ad_requested"))
        print("RETENTION_QA: Pro app open suppression PASS")
    }

    private func launch(pro: Bool, timed: Bool = false, ads: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-device-qa", "-qa-entitlement", pro ? "pro" : "free", "-uitest-reset", "-uitest-skip-onboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if timed { app.launchArguments += ["-device-qa-seed", "-device-qa-timed"] }
        if ads { app.launchArguments.append("-device-qa-ads") }
        app.launch()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30))
        wait(app.staticTexts["qa.dashboard"], pro ? "QA PRO" : "QA FREE", 20)
        return app
    }
    private func wait(_ element: XCUIElement, _ text: String, _ timeout: TimeInterval = 10) {
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \(text), actual \(element.exists ? element.label : "missing")")
    }
    private func shot(_ name: String) {
        let file = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        file.name = name; file.lifetime = .keepAlways; add(file)
    }
    private func enter(_ text: String, _ app: XCUIApplication) {
        let field = app.textFields["today.quickCapture"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(text)
        print("QA typed value: \(String(describing: field.value))")
    }
    private func hideKeyboard(_ app: XCUIApplication) {
        let hide = app.buttons["Hide keyboard"]
        if hide.exists { hide.tap() }
    }
    private func layouts(_ app: XCUIApplication) {
        app.buttons["navigation.settings"].tap()
        let link = app.buttons["settings.savedLayouts"]
        XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        XCTAssertTrue(app.buttons["layouts.save"].waitForExistence(timeout: 10))
    }
    private func saveLayout(_ name: String, _ app: XCUIApplication) {
        app.buttons["layouts.save"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.textFields.firstMatch.typeText(name)
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }
    private func items(_ app: XCUIApplication) -> [[String: Any]] {
        let text = app.staticTexts["qa.storage"].value as? String ?? "[]"
        print("QA persisted items: \(text)")
        let cards = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] ?? []
        return cards.flatMap { $0["checklistItems"] as? [[String: Any]] ?? [] }
    }
    func test01FreeCaptureRepeatGateAndPersistence() {
        let app = launch(pro: false)
        enter("today 3pm QA Appointment", app)
        shot("free-input-before-save")
        XCTAssertTrue(app.buttons["today.quickCapture.save"].isEnabled)
        app.buttons["today.quickCapture.save"].tap()
        shot("free-input-after-save")
        print("QA saved: \(app.staticTexts["qa.dashboard"].label)")
        wait(app.staticTexts["qa.dashboard"], "15:00 QA Appointment")
        XCTAssertEqual(items(app).first?["hasDueTime"] as? Bool, true)
        for (input, title, recurrence) in [("daily QA Stretch", "QA Stretch", "daily"),
                                          ("weekdays QA Office", "QA Office", "weekdays"),
                                          ("weekly QA Laundry", "QA Laundry", "weekly")] {
            enter(input, app); app.buttons["today.quickCapture.save"].tap()
            XCTAssertEqual(items(app).first { $0["text"] as? String == title }?["recurrence"] as? String, recurrence)
        }
        hideKeyboard(app)
        app.buttons["smartRepeat.open"].tap()
        XCTAssertTrue(app.buttons["smartRepeat.save"].waitForExistence(timeout: 5)); app.buttons["smartRepeat.save"].tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10)); shot("free-repeat-paywall")
        app.buttons["paywall.close"].tap(); app.buttons["Cancel"].firstMatch.tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-uitest-reset" }; app.launch()
        wait(app.staticTexts["qa.dashboard"], "QA Appointment", 30); shot("free-capture-persistence")
    }
    func test02FreeLayoutLimitAndAutomaticSwitchGate() {
        let app = launch(pro: false); layouts(app); saveLayout("QA Free Layout", app)
        app.buttons["layouts.save"].tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10)); shot("free-layout-limit")
        app.buttons["paywall.close"].tap(); app.buttons["layouts.smartLockScreen"].tap()
        XCTAssertTrue(app.switches["schedule.enabled"].waitForExistence(timeout: 5)); app.switches["schedule.enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10)); shot("free-schedule-gate")
    }
    func test03ProAdvancedRepeatFourRules() {
        let app = launch(pro: true)
        for (text, option, key) in [
            ("QA Selected Days", "", "selectedWeekdays"),
            ("QA Monthly Last", "Last weekday of each month", "monthlyLastWeekday"),
            ("QA Alternate Week", "Every other week", "biweekly"),
            ("QA Every Three Days", "Every N days", "everyNDays")
        ] {
            enter(text, app); hideKeyboard(app); app.buttons["smartRepeat.open"].tap()
            XCTAssertTrue(app.buttons["smartRepeat.save"].waitForExistence(timeout: 5))
            if !option.isEmpty { app.buttons["smartRepeat.kind"].tap(); app.buttons[option].tap() }
            if key == "biweekly" { app.buttons["smartRepeat.weekday"].tap(); app.buttons["Tuesday"].tap() }
            shot("pro-repeat-\(key)"); app.buttons["smartRepeat.save"].tap(); app.buttons["today.quickCapture.save"].tap()
            let item = items(app).first { $0["text"] as? String == text }
            XCTAssertNotNil((item?["advancedRepeat"] as? [String: Any])?[key], "Saved rule \(key)")
        }
        XCTAssertEqual(items(app).count, 4)
    }
    func test04ProMultipleLayoutsAndOverlapProtection() {
        let app = launch(pro: true); layouts(app)
        saveLayout("QA Personal Layout", app); saveLayout("QA Work Layout", app)
        app.buttons["layouts.smartLockScreen"].tap(); app.buttons["schedule.add"].tap()
        let name = app.textFields["schedule.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("QA Work Rule")
        app.buttons["schedule.save"].tap()
        XCTAssertTrue(app.staticTexts["QA Work Rule"].waitForExistence(timeout: 5)); app.switches["schedule.enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["schedule.enabled"].value as? String, "1")
        app.buttons["schedule.add"].tap(); let second = app.textFields["schedule.name"]
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap(); second.typeText("QA Overlap Rule")
        app.buttons["schedule.save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'overlap'")).firstMatch.exists)
        shot("pro-overlap-protection")
    }
    func test05ProRealClockSwitchAndFallback() {
        let app = launch(pro: true, timed: true); let state = app.staticTexts["qa.dashboard"]
        wait(state, "QA Personal", 15); XCTAssertFalse(state.label.contains("QA Work")); shot("pro-personal-before-boundary")
        wait(state, "QA Work", 145); XCTAssertFalse(state.label.contains("QA Personal")); XCTAssertTrue(state.label.contains("dateTodo")); shot("pro-work-after-boundary")
        wait(state, "QA Personal", 80); XCTAssertTrue(state.label.contains("QA Work")); XCTAssertTrue(state.label.contains("calendarItems")); shot("pro-manual-fallback")
    }
    func test06ProAppleRemindersRoundTrip() {
        let app = launch(pro: true)
        addUIInterruptionMonitor(withDescription: "Reminders access") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "(label CONTAINS[c] 'Allow' OR label CONTAINS '허용') AND NOT label CONTAINS[c] 'Don' AND NOT label CONTAINS '안'")).firstMatch
            if allow.exists { allow.tap(); return true }; return false
        }
        app.buttons["navigation.settings"].tap(); app.buttons["settings.appleReminders"].tap()
        let create = app.buttons["qa.reminder.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap(); app.tap()
        wait(app.staticTexts["qa.reminder.status"], "QA imported", 30)
        app.buttons["navigation.today"].tap(); wait(app.staticTexts["qa.dashboard"], "QA Apple Reminder", 20)
        let todo = app.buttons["QA Apple Reminder"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5)); todo.tap(); shot("pro-reminder-app-completion")
        app.buttons["navigation.settings"].tap(); app.buttons["settings.appleReminders"].tap()
        app.buttons["qa.reminder.verify"].tap(); wait(app.staticTexts["qa.reminder.status"], "QA source completed")
        shot("pro-reminder-source-completion")
    }
    func test07LiveActivityRendersOnDeviceNotificationCenter() {
        let app = launch(pro: true, timed: true)
        let activity = app.staticTexts["qa.activity"]
        if activity.exists && !activity.label.contains("running") {
            let start = app.buttons["Start"].firstMatch
            if start.exists { start.tap() }
        }
        wait(activity, "running", 25)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.005))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.75))
        from.press(forDuration: 0.1, thenDragTo: to)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let task = system.staticTexts.matching(NSPredicate(format: "label CONTAINS 'QA Personal'")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 15), "The actual Live Activity should render the selected task")
        let attachment = XCTAttachment(screenshot: task.screenshot())
        attachment.name = "live-activity-real-system-task"; attachment.lifetime = .keepAlways; add(attachment)
        app.activate()
    }

    func test08FreeAppleRemindersRequiresPro() {
        let app = launch(pro: false)
        app.buttons["navigation.settings"].tap(); app.buttons["settings.appleReminders"].tap()
        let connect = app.buttons["Connect Reminders with Pro"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5)); connect.tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
        shot("free-apple-reminders-paywall")
    }
    func test09AdMobTestAppOpenAndProSuppression() {
        let free = launch(pro: false, ads: true)
        wait(free.staticTexts["qa.ads"], "eligible=true", 15)
        wait(free.staticTexts["qa.ads"], "ad_impression_observed", 60)
        shot("free-admob-official-test-app-open")
        let pro = launch(pro: true, ads: true)
        wait(pro.staticTexts["qa.ads"], "eligible=false", 15)
        XCTAssertFalse(pro.staticTexts["qa.ads"].label.contains("ad_requested"))
        shot("pro-no-advertising")
    }

}
