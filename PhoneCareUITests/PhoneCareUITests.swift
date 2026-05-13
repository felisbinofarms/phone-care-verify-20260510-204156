import XCTest

private enum UITestLaunchArguments {
    static let skipOnboarding = "UITestsSkipOnboarding"
    static let skipStoreKit = "UITestsSkipStoreKit"
}

@MainActor
final class PhoneCareUITests: XCTestCase {
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestLaunchArguments.skipOnboarding,
            UITestLaunchArguments.skipStoreKit
        ]
        return app
    }

    /// Returns the first element with the given accessibility identifier, regardless of element type.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testAppLaunches() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.exists)
    }

    func testMainTabNavigationShowsCoreScreens() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("screen.dashboard", in: app).waitForExistence(timeout: 5))

        app.tabBars.buttons["Storage"].tap()
        XCTAssertTrue(element("screen.storage", in: app).waitForExistence(timeout: 2))

        app.tabBars.buttons["Privacy"].tap()
        XCTAssertTrue(element("screen.privacy", in: app).waitForExistence(timeout: 2))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("screen.settings", in: app).waitForExistence(timeout: 2))
    }

    func testSettingsShowsStableLinksAndToggles() throws {
        let app = makeApp()
        app.launch()

        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.switches["settings.notification.weekly"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["settings.notification.duplicates"].exists)
        XCTAssertTrue(app.switches["settings.notification.battery"].exists)
        XCTAssertTrue(app.buttons["settings.about"].exists)
        XCTAssertTrue(app.buttons["settings.dataPrivacy"].exists)

        app.buttons["settings.about"].tap()
        XCTAssertTrue(element("screen.about", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["about.privacyPolicy"].exists)
        XCTAssertTrue(app.buttons["about.termsOfService"].exists)
        XCTAssertTrue(app.buttons["about.contactSupport"].exists)
        XCTAssertTrue(app.buttons["about.rateApp"].exists)
    }

    func testBatteryTrendFreeTierGatesRangesBeyondOneDay() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(element("screen.dashboard", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.card.battery"].waitForExistence(timeout: 3))
        app.buttons["dashboard.card.battery"].tap()

        XCTAssertTrue(element("screen.battery", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["battery.range.1d"].exists)
        XCTAssertTrue(app.buttons["battery.range.30d"].exists)

        app.buttons["battery.range.30d"].tap()
        XCTAssertTrue(app.staticTexts["battery.premiumGate.message"].waitForExistence(timeout: 3))
    }
}

