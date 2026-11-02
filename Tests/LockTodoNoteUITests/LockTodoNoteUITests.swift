import XCTest
import UIKit
import Vision

/// End-to-end checks for the paths a user cannot afford to have broken:
/// getting through onboarding, capturing a todo, and finding settings.
///
/// Assertions use accessibility identifiers rather than
/// visible text, so the suite keeps working in all nine languages instead of
/// only whichever one the simulator happens to be set to.
final class LockTodoNoteUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Every test starts from a wiped App Group so results never depend on what
    /// the previous run left behind.
    private func launchApp(skipOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        if skipOnboarding {
            app.launchArguments.append("-uitest-skip-onboarding")
        }
        app.launch()
        return app
    }

    // MARK: - Onboarding

    func testOnboardingAppearsOnFirstLaunch() {
        let app = launchApp(skipOnboarding: false)
        XCTAssertTrue(
            app.buttons["onboarding.primary"].waitForExistence(timeout: 15),
            "a fresh install should land on onboarding"
        )
        XCTAssertTrue(app.buttons["onboarding.skip"].exists)
        XCTAssertFalse(
            app.buttons["navigation.today"].isHittable,
            "the main navigation is covered while onboarding is up"
        )
    }

    func testOnboardingCapturesTheFirstTodo() {
        let app = launchApp(skipOnboarding: false)
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        primary.tap()

        let field = app.textFields["onboarding.todoField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Typing without tapping first proves the field auto-focuses.
        field.typeText("Call the clinic")

        XCTAssertTrue(primary.isEnabled, "the primary button unlocks once there is text")
        primary.tap()

        XCTAssertTrue(
            app.staticTexts["Call the clinic"].waitForExistence(timeout: 5),
            "the preview should show the todo just entered"
        )
    }

    func testPrimaryButtonStaysDisabledWithoutText() {
        let app = launchApp(skipOnboarding: false)
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        primary.tap()

        XCTAssertTrue(app.textFields["onboarding.todoField"].waitForExistence(timeout: 5))
        XCTAssertFalse(primary.isEnabled, "an empty todo cannot be submitted")
    }

    func testOnboardingCanBeSkipped() {
        let app = launchApp(skipOnboarding: false)
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()

        XCTAssertTrue(
            app.buttons["navigation.today"].waitForExistence(timeout: 5),
            "skipping lands on the main app"
        )
    }

    // MARK: - Main app

    func testTopDestinationsAreReachable() {
        let app = launchApp(skipOnboarding: true)
        let today = app.buttons["navigation.today"]
        let calendar = app.buttons["navigation.calendar"]
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        XCTAssertTrue(calendar.exists)
        XCTAssertTrue(settings.exists)

        calendar.tap()
        XCTAssertTrue(calendar.isSelected)
        today.tap()
        XCTAssertTrue(today.isSelected)
        settings.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5)
        )
    }

    func testAddingATodo() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))

        addTodo("Buy milk", in: app)

        XCTAssertTrue(
            app.staticTexts["Buy milk"].waitForExistence(timeout: 5),
            "the todo should appear in the list"
        )
    }

    func testCompletingATodoKeepsItVisible() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))
        addTodo("Water the plants", in: app)

        let todo = app.buttons["Water the plants"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        XCTAssertTrue(
            todo.waitForNonExistence(timeout: 5),
            "a completed todo should leave the pending list"
        )
    }

    func testTodoSurvivesRelaunch() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))
        addTodo("Persisted item", in: app)
        XCTAssertTrue(app.staticTexts["Persisted item"].waitForExistence(timeout: 5))

        // Relaunch *without* the reset flag so stored data is kept. This is the
        // migration guarantee in miniature: what was saved must come back.
        app.terminate()
        let relaunched = XCUIApplication()
        // Without -uitest- flags a debug build shows its launch app open ad.
        relaunched.launchArguments = ["-disable-test-ads"]
        relaunched.launch()

        XCTAssertTrue(
            relaunched.staticTexts["Persisted item"].waitForExistence(timeout: 15),
            "todos must survive a relaunch"
        )
    }

    // MARK: - Templates

    /// Template selection now lives inline on the home screen rather than
    /// behind a separate picker screen.
    func testTemplatePickerIsOnHomeWithDefaultSelected() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))
        expandTemplateSection(in: app)

        let defaultTemplate = app.descendants(matching: .any)["template.calendarItems"]
        XCTAssertTrue(reveal(defaultTemplate, in: app))
        XCTAssertTrue(defaultTemplate.isSelected, "Calendar + Items is the default")
    }

    func testSelectingAFreeTemplateMovesTheSelection() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))
        expandTemplateSection(in: app)

        let free = app.descendants(matching: .any)["template.dateTodo"]
        XCTAssertTrue(reveal(free, in: app))
        free.tap()

        XCTAssertTrue(free.isSelected, "a free template applies immediately")
        XCTAssertFalse(app.descendants(matching: .any)["template.calendarItems"].isSelected)
    }

    /// A locked template must explain itself before asking for money, so it
    /// opens an info sheet rather than applying or jumping straight to pricing.
    func testProTemplateDoesNotApplyForFreeUsers() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))
        expandTemplateSection(in: app)

        let pro = app.descendants(matching: .any)["template.memoTodo"]
        XCTAssertTrue(reveal(pro, in: app))
        pro.tap()

        XCTAssertFalse(pro.isSelected, "a locked template is never applied for free")
        XCTAssertTrue(
            app.descendants(matching: .any)["template.calendarItems"].isSelected,
            "the previous selection stays put"
        )
    }

    // MARK: - Helpers

    private func expandTemplateSection(in app: XCUIApplication) {
        let toggle = app.buttons["home.templateSection.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
    }

    private func addTodo(_ text: String, in app: XCUIApplication) {
        let editor = app.textFields["today.quickCapture"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(text)

        let save = app.buttons["today.quickCapture.save"]
        XCTAssertTrue(save.isEnabled, "Save unlocks once there is text")
        save.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let scrollView = app.scrollViews["home.scroll"]
        for _ in 0..<4 {
            if element.exists, element.isHittable { return true }
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return element.exists && element.isHittable
    }
}

@MainActor
final class ReviewRegressionUITests: XCTestCase {
    private var restoreActivitiesDisabled = false

    private func setLiveActivitiesAllowed(_ allowed: Bool, app: XCUIApplication) {
        app.activate()
        let open = app.buttons["qa.settings.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        let match = NSPredicate(format: "label CONTAINS[c] 'Live Activit' OR label CONTAINS '실시간 현황'")
        let toggle = settings.switches.matching(match).firstMatch
        if !toggle.waitForExistence(timeout: 3) {
            let row = settings.cells.matching(match).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() }
            else {
                let button = settings.buttons.matching(match).firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 3), "Live Activities setting row: \(settings.debugDescription)")
                button.tap()
            }
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Live Activities switch: \(settings.debugDescription)")
        let desired = allowed ? "1" : "0"
        let current = String(describing: toggle.value ?? "")
        print("IPAD_ACTIVITY_SETTING before: \(current); desired: \(desired)")
        let isOn = (toggle.value as? NSNumber)?.boolValue ?? ["1", "true"].contains(current.lowercased())
        if isOn != allowed {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        print("IPAD_ACTIVITY_SETTING after: \(String(describing: toggle.value ?? ""))")
        screenshot(allowed ? "ipad-live-activities-enabled-setting" : "ipad-live-activities-restored-setting")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR value == %@", desired, NSNumber(value: allowed)), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Switch value: \(String(describing: toggle.value ?? ""))")
        app.activate()
    }

    override func tearDown() async throws {
        #if !targetEnvironment(simulator)
        await MainActor.run {
            let app = XCUIApplication()
            if restoreActivitiesDisabled { setLiveActivitiesAllowed(false, app: app) }
            app.terminate()
            app.launchArguments = ["-device-qa", "-device-qa-restore"]
            app.launch()
            XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 60), "Original iPad data must be restored after each QA test")
            app.terminate()
            app.launchArguments = []
            app.launch()
        }
        #endif
        try await super.tearDown()
    }

    private func launch(day: Int = 28, month: Int = 10, reset: Bool = false, pro: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        let date = String(format: "2026-%02d-%02dT12:00:00", month, day)
        app.launchArguments = ["-device-qa", "-qa-entitlement", pro ? "pro" : "free", "-qa-now", date, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments += ["-uitest-reset", "-uitest-skip-onboarding", "-device-qa-seed", "-qa-review-seed"] }
        app.launch()
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 30))
        return app
    }
    private func reveal(_ button: XCUIElement, app: XCUIApplication) {
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
    }
    private func storage(_ app: XCUIApplication) throws -> [[String: Any]] {
        let element = app.staticTexts["qa.storage"]
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data((element.value as? String ?? "[]").utf8)) as? [[String: Any]])
    }
    private func visibleItems(_ app: XCUIApplication) throws -> [[String: Any]] {
        try storage(app).flatMap { $0["checklistItems"] as? [[String: Any]] ?? [] }
    }
    private func hasDog(_ app: XCUIApplication) throws -> Bool {
        try visibleItems(app).contains { $0["text"] as? String == "Walk my dog" }
    }
    private func screenshot(_ name: String, element: XCUIElement? = nil) {
        let attachment = XCTAttachment(screenshot: element?.screenshot() ?? XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testStopFutureRepeatsAndRelaunchNextDays() throws {
        continueAfterFailure = false
        var app = launch(reset: true)
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); screenshot("review-before-delete"); delete.tap()
        let stop = app.buttons["Stop future repeats"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); screenshot("review-delete-scopes"); stop.tap()
        XCTAssertFalse(try hasDog(app))
        XCTAssertTrue(try visibleItems(app).contains { $0["id"] as? String == "qa-sibling" })
        XCTAssertFalse(app.staticTexts["qa.dashboard"].label.contains("Walk my dog"))
        screenshot("review-stopped-with-sibling-preserved")
        app.buttons["qa.advanceDay"].tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-29"))
        XCTAssertFalse(try hasDog(app))
        screenshot("review-running-date-boundary")
        for day in [28, 29, 30] {
            app.terminate(); app = launch(day: day)
            XCTAssertFalse(try hasDog(app))
            XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-\(day)"))
            XCTAssertFalse(app.staticTexts["qa.dashboard"].label.contains("Walk my dog"))
        }
        screenshot("review-next-day-auto-without-dog")
    }
    func testTodayOnlyAndOrdinaryDeletion() throws {
        continueAfterFailure = false
        var app = launch(reset: true)
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap()
        app.buttons["Delete this day only"].tap()
        XCTAssertFalse(try hasDog(app))
        app.terminate(); app = launch()
        XCTAssertFalse(try hasDog(app))
        app.terminate(); app = launch(day: 29)
        XCTAssertTrue(try hasDog(app))
        let ordinary = app.buttons["todo.delete.qa-dog:qa-sibling"]
        reveal(ordinary, app: app); ordinary.tap()
        XCTAssertFalse(try visibleItems(app).contains { $0["id"] as? String == "qa-sibling" })
        app.terminate(); app = launch(day: 30)
        XCTAssertFalse(try visibleItems(app).contains { $0["id"] as? String == "qa-sibling" })
        XCTAssertTrue(try hasDog(app))
        screenshot("review-today-only-next-occurrence")
    }
    func testEditorDeletionDismissesAndPreservesOtherTask() throws {
        continueAfterFailure = false
        let app = launch(reset: true)
        let edit = app.buttons["todo.edit.qa-dog:qa-sibling"]
        reveal(edit, app: app); edit.tap()
        let delete = app.buttons["todo.editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.textFields["todo.editor.text"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertFalse(try visibleItems(app).contains { $0["id"] as? String == "qa-sibling" })
        XCTAssertTrue(try hasDog(app))
        screenshot("review-editor-deletion-dismissed")
    }
    func testEntireSeriesConfirmation() throws {
        continueAfterFailure = false
        var app = launch(reset: true)
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap()
        app.buttons["Delete entire series…"].tap()
        let alert = app.alerts["Delete entire series?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["All occurrences, including past completion history, will be deleted."].exists)
        screenshot("review-entire-series-confirmation"); alert.buttons["Delete"].tap()
        XCTAssertFalse(try hasDog(app))
        XCTAssertTrue(try storage(app).allSatisfy { ($0["recurrenceRules"] as? [[String: Any]] ?? []).isEmpty })
        app.terminate(); app = launch(day: 29)
        XCTAssertFalse(try hasDog(app))
    }
    func testLiveActivityReflectsDeletionOnSystemSurface() throws {
        continueAfterFailure = false
        let app = launch(reset: true)
        print("IPAD_ACTIVITY before start: \(app.staticTexts["qa.activity"].label)")
        if app.staticTexts["qa.activity"].label.contains("unsupported_disabled") {
            restoreActivitiesDisabled = true
            setLiveActivitiesAllowed(true, app: app)
        }
        let start = app.buttons["Start"].firstMatch
        if start.waitForExistence(timeout: 5), start.isHittable { start.tap() }
        screenshot("ipad-live-activity-start-state")
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'running'"), object: app.staticTexts["qa.activity"])
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 25), .completed, "Activity status: \(app.staticTexts["qa.activity"].label); alerts: \(app.alerts.debugDescription)")
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap(); app.buttons["Stop future repeats"].tap()
        XCTAssertFalse(try hasDog(app))
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label CONTAINS 'Walk my dog'"), object: app.staticTexts["qa.dashboard"])
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 10), .completed)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.005))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.75))
        from.press(forDuration: 0.1, thenDragTo: to)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let sibling = system.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Keep this task'")).firstMatch
        XCTAssertTrue(sibling.waitForExistence(timeout: 15), "Actual Live Activity must preserve the other task")
        XCTAssertFalse(system.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Walk my dog'")).firstMatch.exists)
        XCTAssertTrue(sibling.isHittable)
        screenshot("review-system-live-activity-after-delete", element: sibling)
        app.activate()
    }
    func testFreeModeStopRemainsDeletedNextWeek() throws {
        continueAfterFailure = false
        var app = launch(reset: true, pro: false)
        XCTAssertTrue(app.staticTexts["qa.dashboard"].label.contains("QA FREE"))
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap(); app.buttons["Stop future repeats"].tap()
        XCTAssertFalse(try hasDog(app))
        app.buttons["qa.advanceDay"].tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-29"))
        app.terminate(); app = launch(day: 4, month: 11, pro: false)
        XCTAssertTrue(app.staticTexts["qa.dashboard"].label.contains("QA FREE"))
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-11-04"))
        XCTAssertFalse(try hasDog(app))
        XCTAssertTrue(try visibleItems(app).contains { $0["id"] as? String == "qa-sibling" })
        screenshot("ipad-free-next-week-still-deleted")
    }

    func testHomeWidgetReflectsDeletionOnDevice() throws {
        continueAfterFailure = false
        let app = launch(reset: true)
        app.buttons["qa.activity.stop"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func findHomeTask(_ text: String) -> XCUIElement {
            XCUIDevice.shared.press(.home)
            let task = system.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            if task.waitForExistence(timeout: 5), task.isHittable { return task }
            for _ in 0..<5 where !task.isHittable { system.swipeRight() }
            for _ in 0..<8 where !task.isHittable { system.swipeLeft() }
            return task
        }
        let before = findHomeTask("Walk my dog")
        XCTAssertTrue(before.waitForExistence(timeout: 45)); XCTAssertTrue(before.isHittable)
        screenshot("ipad-home-widget-before-delete")
        app.activate()
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap(); app.buttons["Stop future repeats"].tap()
        XCTAssertFalse(try hasDog(app))
        let remaining = findHomeTask("Keep this task")
        XCTAssertTrue(remaining.waitForExistence(timeout: 45)); XCTAssertTrue(remaining.isHittable)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: before)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 45), .completed)
        screenshot("ipad-home-widget-after-delete")
        app.activate()
    }

    /// The real accessory widget exposes one generic accessibility button on
    /// iPadOS. Verify its actual rendered pixels rather than requiring text nodes.
    private func widgetText(_ element: XCUIElement) throws -> String {
        let pixels = try XCTUnwrap(element.screenshot().image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: pixels).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testInstalledLockWidgetReflectsDeletionWithoutLiveActivity() throws {
        continueAfterFailure = false
        var app = launch(reset: true)
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'known=true'"), object: app.staticTexts["qa.widget"])
        XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 25), .completed)
        print("IPAD_WIDGET_CONFIGURATION: \(app.staticTexts["qa.widget"].label)")
        app.buttons["qa.activity.stop"].tap()
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label CONTAINS 'running'"), object: app.staticTexts["qa.activity"])
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func showLockScreen() {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.005))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.75))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        let widget = system.buttons["com.namslab.glancecard.widget:GlanceCardLockScreenWidget"]
        var before = ""
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            app.activate()
            XCUIDevice.shared.orientation = orientation
            showLockScreen()
            if widget.waitForExistence(timeout: 10), widget.isHittable {
                before = try widgetText(widget)
                screenshot("ipad-lock-widget-before-delete-without-activity", element: widget)
                if before.localizedCaseInsensitiveContains("Walk my dog") { break }
            }
        }
        print("IPAD_ACCESSORY_OCR before: \(before)")
        XCTAssertTrue(before.localizedCaseInsensitiveContains("Walk my dog"), "Actual accessory pixels: \(before)")
        app.activate()
        let delete = app.buttons["todo.delete.qa-dog:qa-dog-item"]
        reveal(delete, app: app); delete.tap(); app.buttons["Stop future repeats"].tap()
        XCTAssertFalse(try hasDog(app))
        showLockScreen()
        XCTAssertTrue(widget.waitForExistence(timeout: 15)); XCTAssertTrue(widget.isHittable)
        var after = ""
        let deadline = Date().addingTimeInterval(15)
        repeat {
            after = try widgetText(widget)
            if after.localizedCaseInsensitiveContains("Keep this task"), !after.localizedCaseInsensitiveContains("Walk my dog") { break }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        if after.localizedCaseInsensitiveContains("Walk my dog") {
            // WidgetKit may defer invalidation. Also exercise the required cold
            // relaunch boundary, without resetting cards or the stopped series.
            screenshot("ipad-lock-widget-os-deferred-update", element: widget)
            app.terminate()
            app = launch()
            XCTAssertFalse(try hasDog(app))
            showLockScreen()
            XCTAssertTrue(widget.waitForExistence(timeout: 15))
            let retryDeadline = Date().addingTimeInterval(45)
            repeat {
                after = try widgetText(widget)
                if after.localizedCaseInsensitiveContains("Keep this task"), !after.localizedCaseInsensitiveContains("Walk my dog") { break }
                Thread.sleep(forTimeInterval: 1)
            } while Date() < retryDeadline
            print("IPAD_ACCESSORY_REFRESH used cold relaunch after OS deferral")
        }
        print("IPAD_ACCESSORY_OCR after: \(after)")
        let screenTime = Date().timeIntervalSince1970
        screenshot("ipad-lock-widget-after-delete-without-activity", element: widget)
        app.activate()
        print("IPAD_WIDGET_TIMELINES screenAt=\(screenTime): \(app.staticTexts["qa.timelines"].value ?? "missing")")
        XCTAssertTrue(after.localizedCaseInsensitiveContains("Keep this task"), "Actual accessory pixels: \(after)")
        XCTAssertFalse(after.localizedCaseInsensitiveContains("Walk my dog"))
    }

    func testAppleRemindersRoundTripOnQAList() throws {
        continueAfterFailure = false
        let app = launch(reset: true)
        addUIInterruptionMonitor(withDescription: "Reminders access") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "(label CONTAINS[c] 'Allow' OR label CONTAINS '허용') AND NOT label CONTAINS[c] 'Don' AND NOT label CONTAINS '안'")).firstMatch
            if allow.exists { allow.tap(); return true }; return false
        }
        app.buttons["navigation.settings"].tap(); app.buttons["settings.appleReminders"].tap()
        let create = app.buttons["qa.reminder.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap(); app.tap()
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'QA imported'"), object: app.staticTexts["qa.reminder.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 40), .completed)
        app.buttons["navigation.today"].tap()
        let todo = app.buttons["QA Apple Reminder"]
        reveal(todo, app: app); todo.tap()
        app.buttons["navigation.settings"].tap(); app.buttons["settings.appleReminders"].tap()
        app.buttons["qa.reminder.verify"].tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'QA source completed'"), object: app.staticTexts["qa.reminder.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        screenshot("ipad-reminders-source-completed")
    }

    func testCalendarBrowsingPinAndFollowTodayPersist() throws {
        continueAfterFailure = false
        var app = launch(reset: true)
        app.buttons["navigation.calendar"].tap()
        let day = app.buttons["calendar.day.2026-10-27"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-28"))
        app.buttons["calendar.pinDate"].tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("pinned 2026-10-27"))
        app.buttons["navigation.today"].tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("pinned 2026-10-27"))
        screenshot("review-explicit-pinned-date")
        app.terminate(); app = launch(day: 29)
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("pinned 2026-10-27"))
        app.buttons["dashboard.followToday"].tap()
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-29"))
        app.terminate(); app = launch(day: 30)
        XCTAssertTrue(app.staticTexts["qa.date"].label.contains("auto 2026-10-30"))
        screenshot("review-follow-today-restored")
    }
}


/// Leaves the user's requested Lock Screen feature enabled, using existing data.
@MainActor
final class LiveActivityPermissionRecoveryUITests: XCTestCase {
    func testEnableAndStartWithExistingData() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 60))
        let action = app.buttons["liveActivity.action"]
        for _ in 0..<5 where !action.isHittable { app.swipeUp() }
        XCTAssertTrue(action.isHittable)
        let status = app.staticTexts["liveActivity.status"]
        if status.label.contains("설정") || status.label.contains("Settings") {
            XCTAssertTrue(action.isEnabled)
            action.tap()
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
            let match = NSPredicate(format: "label CONTAINS[c] 'Live Activit' OR label CONTAINS '실시간 현황'")
            let toggle = settings.switches.matching(match).firstMatch
            if !toggle.waitForExistence(timeout: 3) {
                let row = settings.cells.matching(match).firstMatch
                if row.exists { row.tap() }
                else { settings.buttons.matching(match).firstMatch.tap() }
            }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if String(describing: toggle.value ?? "") != "1" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            }
            XCTAssertEqual(String(describing: toggle.value ?? ""), "1")
            app.activate()
        }
        if !status.label.contains("LIVE") { action.tap() }
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'LIVE'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 20), .completed)
        // Keep the successfully started activity and permission enabled for the user.
        app.terminate()
        app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        XCTAssertTrue(status.label.contains("LIVE"))
    }
}

/// Release-only, non-resetting checks on the connected iPad. Never run the
/// reset/seed suites against this installation or touch pre-existing records.
@MainActor
final class Release122IPadUITests: XCTestCase {
    private var ownedTodoName: String?
    private var ownedMemoName: String?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() throws -> XCUIApplication {
        #if targetEnvironment(simulator)
        throw XCTSkip("This suite is for the physical iPad")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-FIRDebugEnabled", "-FIRAnalyticsDebugEnabled"]
        app.launch()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 45))
        return app
        #endif
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable {
            let predicate = element.identifier.isEmpty
                ? NSPredicate(format: "label == %@", element.label)
                : NSPredicate(format: "identifier == %@", element.identifier)
            // Today has a task-list scroll view inside the page scroll view.
            let parents = app.scrollViews.containing(predicate).allElementsBoundByIndex
            let scroll = parents.min { $0.frame.height < $1.frame.height }
                ?? app.scrollViews["home.scroll"]
            if element.exists && element.frame.midY < scroll.frame.midY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "Required existing control must be reachable")
    }

    private func mode(_ memo: Bool, in app: XCUIApplication) {
        let names = memo ? ["메모", "Memo"] : ["할 일", "Todo"]
        let button = app.segmentedControls.buttons.matching(NSPredicate(format: "label IN %@", names)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        reveal(button, in: app)
        button.tap()
    }

    private func selectedTemplate(in app: XCUIApplication) -> String {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'template.'"))
            .allElementsBoundByIndex.first { $0.isSelected }?.identifier ?? "unknown"
    }

    private func write(_ text: String, in app: XCUIApplication) {
        let editor = app.descendants(matching: .any)["today.quickCapture"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        reveal(editor, in: app)
        editor.tap()
        editor.typeText(text)
        let save = app.buttons["today.quickCapture.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
    }

    private func todo(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'todo.toggle.' AND label == %@", name)).firstMatch
    }

    private func expandCompleted(in app: XCUIApplication) {
        let group = app.buttons.matching(NSPredicate(format: "label CONTAINS '완료됨' OR label CONTAINS[c] 'Completed'")).firstMatch
        if group.exists { reveal(group, in: app); group.tap() }
    }

    private func createTodo(in app: XCUIApplication) -> String {
        app.buttons["navigation.today"].tap()
        mode(false, in: app)
        let name = "L122-iPad-task-\(Int(Date().timeIntervalSince1970))"
        ownedTodoName = name
        write(name, in: app)
        XCTAssertTrue(todo(name, in: app).waitForExistence(timeout: 10))
        return name
    }

    private func removeOwnedTodo(in app: XCUIApplication) {
        guard let name = ownedTodoName else { return }
        app.buttons["navigation.today"].tap()
        mode(false, in: app)
        var row = todo(name, in: app)
        if !row.exists { expandCompleted(in: app); row = todo(name, in: app) }
        guard row.exists else { ownedTodoName = nil; return }
        XCTAssertEqual(row.label, name)
        let suffix = String(row.identifier.dropFirst("todo.toggle.".count))
        let delete = app.buttons["todo.delete.\(suffix)"]
        reveal(delete, in: app)
        delete.tap()
        XCTAssertFalse(row.exists)
        ownedTodoName = nil
    }

    private func removeOwnedMemo(in app: XCUIApplication) {
        guard let name = ownedMemoName else { return }
        app.buttons["navigation.today"].tap()
        mode(true, in: app)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        guard row.exists else { ownedMemoName = nil; return }
        reveal(row, in: app)
        let deletes = app.buttons.matching(NSPredicate(format: "label IN %@", ["삭제", "Delete"]))
            .allElementsBoundByIndex.filter { $0.isHittable && abs($0.frame.midY - row.frame.midY) < 35 }
        XCTAssertEqual(deletes.count, 1, "Only the newly created memo's delete control is eligible")
        guard let delete = deletes.first, deletes.count == 1 else { return }
        delete.tap()
        XCTAssertFalse(row.exists)
        ownedMemoName = nil
    }

    override func tearDown() async throws {
        await MainActor.run {
            let app = XCUIApplication()
            if ownedTodoName != nil || ownedMemoName != nil {
                app.activate()
                removeOwnedTodo(in: app)
                removeOwnedMemo(in: app)
            }
            if app.buttons["navigation.today"].exists {
                app.buttons["navigation.today"].tap()
                mode(false, in: app)
            }
        }
        try await super.tearDown()
    }

    func test00CleanInterruptedReleaseFixtures() throws {
        let app = try launch()
        // Exact disposable records created by the interrupted October 31 run.
        for name in ["L122-iPad-task-1793405615", "L122-iPad-task-1793405534"] {
            ownedTodoName = name
            removeOwnedTodo(in: app)
        }
    }

    func test01UpgradeAndSettingsWithoutReset() throws {
        let app = try launch()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        XCTAssertFalse(app.buttons["smartRepeat.open"].exists, "Smart Repeat moved off Today")
        app.buttons["navigation.settings"].tap()
        let toggle = app.switches["settings.smartRepeat.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(String(describing: toggle.value ?? ""), "1", "Previously unset Smart Repeat defaults ON")
        XCTAssertTrue(app.buttons["smartRepeat.open"].exists)
        XCTAssertTrue(app.buttons["settings.savedLayouts"].exists)
        let attachment = XCTAttachment(screenshot: toggle.screenshot())
        attachment.name = "ipad-release-smart-repeat-default-on"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["navigation.today"].tap()
    }

    func test02TodoCompleteUndoRelaunchAndOwnCleanup() throws {
        let app = try launch()
        let name = createTodo(in: app)
        let row = todo(name, in: app)
        reveal(row, in: app)
        row.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30))
        mode(false, in: app)
        expandCompleted(in: app)
        let completed = todo(name, in: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        reveal(completed, in: app)
        completed.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30))
        XCTAssertTrue(todo(name, in: app).waitForExistence(timeout: 10))
        removeOwnedTodo(in: app)
    }

    func test03RecordOnlyMemoPreservesDisplay() throws {
        let app = try launch()
        let template = selectedTemplate(in: app)
        XCTAssertNotEqual(template, "unknown")
        mode(true, in: app)
        XCTAssertEqual(selectedTemplate(in: app), template)
        let display = app.switches["today.memo.showOnLockScreen"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        if display.isEnabled && String(describing: display.value ?? "") == "1" { display.tap() }
        let name = "L122-iPad-memo-\(Int(Date().timeIntervalSince1970))"
        ownedMemoName = name
        write(name, in: app)
        XCTAssertEqual(selectedTemplate(in: app), template)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 30))
        mode(true, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(selectedTemplate(in: app), template)
        removeOwnedMemo(in: app)
    }

    func test04SystemLiveActivityCompletesOwnTask() throws {
        let app = try launch()
        let name = createTodo(in: app)
        let status = app.staticTexts["liveActivity.status"]
        let action = app.buttons["liveActivity.action"]
        for _ in 0..<7 where !action.isHittable { app.swipeDown() }
        XCTAssertTrue(action.isHittable)
        if !status.label.contains("LIVE") { action.tap() }
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'LIVE'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 20), .completed)
        XCUIDevice.shared.press(.home)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        system.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: system.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.75)))
        let button = system.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "The real system Live Activity must expose the QA task")
        XCTAssertTrue(button.isHittable)
        button.tap()
        app.activate()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 20))
        mode(false, in: app)
        XCTAssertFalse(todo(name, in: app).exists, "Outside completion should leave the pending group")
        expandCompleted(in: app)
        XCTAssertTrue(todo(name, in: app).waitForExistence(timeout: 10))
        removeOwnedTodo(in: app)
    }
}
