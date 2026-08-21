import XCTest

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
        let display = app.buttons["navigation.display"]
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        XCTAssertTrue(calendar.exists)
        XCTAssertTrue(display.exists)
        XCTAssertTrue(settings.exists)

        calendar.tap()
        XCTAssertTrue(calendar.isSelected)
        display.tap()
        XCTAssertTrue(display.isSelected)
        today.tap()
        XCTAssertTrue(today.isSelected)
        settings.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
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

        let todo = app.staticTexts["Water the plants"]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        todo.tap()

        // Completion strikes the row through rather than removing it, so the
        // user can undo by tapping again.
        XCTAssertTrue(todo.exists)
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
        relaunched.launchArguments = []
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

        let defaultTemplate = app.buttons["template.calendarItems"]
        XCTAssertTrue(defaultTemplate.waitForExistence(timeout: 5))
        XCTAssertTrue(defaultTemplate.isSelected, "Calendar + Items is the default")
    }

    func testSelectingAFreeTemplateMovesTheSelection() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))

        let free = app.buttons["template.dateTodo"]
        XCTAssertTrue(free.waitForExistence(timeout: 5))
        free.tap()

        XCTAssertTrue(free.isSelected, "a free template applies immediately")
        XCTAssertFalse(app.buttons["template.calendarItems"].isSelected)
    }

    /// A locked template must explain itself before asking for money, so it
    /// opens an info sheet rather than applying or jumping straight to pricing.
    func testProTemplateDoesNotApplyForFreeUsers() {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(app.buttons["navigation.today"].waitForExistence(timeout: 15))

        let pro = app.buttons["template.memoTodo"]
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        pro.tap()

        XCTAssertFalse(pro.isSelected, "a locked template is never applied for free")
        XCTAssertTrue(
            app.buttons["template.calendarItems"].isSelected,
            "the previous selection stays put"
        )
    }

    // MARK: - Helpers

    private func addTodo(_ text: String, in app: XCUIApplication) {
        let editor = app.textFields["today.quickCapture"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(text)

        let save = app.buttons["today.quickCapture.save"]
        XCTAssertTrue(save.isEnabled, "Save unlocks once there is text")
        save.tap()
    }
}
