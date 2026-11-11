import XCTest

/// Runs Apple's built-in accessibility audit (the same checks as Accessibility
/// Inspector: contrast, element labels, hit-target size, Dynamic Type, clipped
/// text, traits) on the main screens, plus launches at the largest text size and
/// in Bengali. App Review flags apps that are unusable with VoiceOver or large text.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testOnboarding() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 10))
        try audit(app)
    }

    @MainActor
    func testGroupsScreen() throws {
        let app = launch()
        completeOnboardingIfNeeded(app)
        XCTAssertTrue(app.staticTexts["No groups yet"].waitForExistence(timeout: 10))
        try audit(app)
    }

    @MainActor
    func testNewGroupSheet() throws {
        let app = launch()
        completeOnboardingIfNeeded(app)
        app.buttons["Create a group"].tap()
        XCTAssertTrue(app.navigationBars["New group"].waitForExistence(timeout: 5))
        try audit(app)
    }

    @MainActor
    func testProfileScreen() throws {
        let app = launch()
        completeOnboardingIfNeeded(app)
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Profile"].firstMatch.waitForExistence(timeout: 5))
        try audit(app)
    }

    @MainActor
    func testLargestTextSizeLaunches() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try audit(app, for: [.dynamicType, .textClipped])
    }

    @MainActor
    func testBengaliLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguage", "bn", "-AppleLanguages", "(bn)", "-AppleLocale", "bn_BD"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try audit(app, for: [.textClipped, .sufficientElementDescription])
    }

    // MARK: Helpers

    @MainActor
    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Start in English so the queries above match.
        app.launchArguments += ["-appLanguage", "en", "-AppleLanguages", "(en)"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// First launch shows language, account and name steps. The profile lives in
    /// the app's database, so this only runs once per simulator install.
    @MainActor
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        guard app.buttons["Continue without account"].exists
            || app.buttons["English"].waitForExistence(timeout: 3) else { return }
        if app.buttons["English"].exists {
            app.buttons["English"].tap()
            app.buttons["Continue"].tap()
        }
        app.buttons["Continue without account"].tap()
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Sabit")
        app.buttons["Start splitting"].tap()
    }

    /// Runs the audit, ignoring only contrast and Dynamic Type reports on standard
    /// navigation-bar buttons (Cancel, Create, Back). Those are drawn by UIKit with
    /// the system font and the app's tint; the audit flags them on some OS versions
    /// even though the app can't style them further. Everything else fails the test.
    @MainActor
    private func audit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            guard issue.auditType == .contrast || issue.auditType == .dynamicType,
                  let element = issue.element,
                  element.elementType == .button else { return false }
            let navButtons = app.navigationBars.buttons.allElementsBoundByIndex.map(\.identifier)
                + app.navigationBars.buttons.allElementsBoundByIndex.map(\.label)
            let isNavBarButton = navButtons.contains(element.label) || navButtons.contains(element.identifier)
            if isNavBarButton {
                print("Ignored system navigation-bar audit issue: \(issue.compactDescription) on \(element.label)")
            }
            return isNavBarButton
        }
    }
}
