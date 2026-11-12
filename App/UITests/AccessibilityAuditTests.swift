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
    // Named to sort first: XCTest runs tests alphabetically on one install, and the
    // other tests complete onboarding.
    func testA_Onboarding() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        // First launch after install is slow on CI; the audit times out if it starts
        // while the app is still settling.
        sleep(3)
        try audit(app)
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
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
        let sheetBar = app.navigationBars["New group"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        // The Groups screen shows above the sheet under the system dimming. The audit
        // measures that dimmed text too; only the sheet's own elements count here.
        try audit(app, ignoringContrastAbove: sheetBar.frame.minY)
    }

    @MainActor
    func testSettingsScreen() throws {
        let app = launch()
        completeOnboardingIfNeeded(app)
        app.buttons["Account"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try audit(app)
    }

    @MainActor
    func testAccountScreen() throws {
        let app = launch()
        completeOnboardingIfNeeded(app)
        app.buttons["Account"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
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
        app.launchArguments += ["-appLanguage", "bn", "-AppleLanguages", "(bn)", "-AppleLocale", "bn_BD", "-holdTexture", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try audit(app, for: [.textClipped, .sufficientElementDescription])
    }

    // MARK: Helpers

    @MainActor
    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Start in English so the queries above match.
        // Hold the background lines still; the audit times out while anything animates.
        app.launchArguments += ["-appLanguage", "en", "-AppleLanguages", "(en)", "-holdTexture", "YES"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// First launch shows welcome, where you're from, language, account and name steps.
    /// The profile lives in the app's database, so this only runs once per simulator install.
    @MainActor
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let started = app.buttons["Get started"].waitForExistence(timeout: 3)
        guard started || app.buttons["Continue"].exists || app.buttons["Continue without account"].exists else { return }
        if started { app.buttons["Get started"].tap() }
        // Where you're from: the suggestion is already picked.
        if app.buttons["Continue"].waitForExistence(timeout: 3), !app.buttons["English"].exists {
            app.buttons["Continue"].tap()
        }
        if app.buttons["English"].waitForExistence(timeout: 3) {
            app.buttons["English"].tap()
            app.buttons["Continue"].tap()
        }
        app.buttons["Continue without account"].tap()
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Sabit\n") // Return submits, like the Start splitting button.
        if app.buttons["Start splitting"].exists { app.buttons["Start splitting"].tap() }
    }

    /// Runs the audit, ignoring only contrast and Dynamic Type reports on standard
    /// navigation-bar buttons (Cancel, Create, Back). Those are drawn by UIKit with
    /// the system font and the app's tint; the audit flags them on some OS versions
    /// even though the app can't style them further. Everything else fails the test.
    @MainActor
    private func audit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all,
                       ignoringContrastAbove sheetTop: CGFloat? = nil) throws {
        var savedScreenshot = false
        try app.performAccessibilityAudit(for: types) { issue in
            let label = issue.element?.label ?? "(no element)"
            if issue.auditType == .contrast, let sheetTop, let element = issue.element,
               element.frame.maxY <= sheetTop {
                print("Ignored contrast on dimmed content behind the sheet: \(label)")
                return true
            }
            if issue.auditType == .contrast || issue.auditType == .dynamicType,
               let element = issue.element, element.elementType == .button {
                let navButtons = app.navigationBars.buttons.allElementsBoundByIndex
                if navButtons.contains(where: { $0.label == element.label }) {
                    print("Ignored system navigation-bar audit issue: \(issue.compactDescription) on \(label)")
                    return true
                }
            }
            // The audit sometimes names no element. Keep one screenshot per audit so CI
            // can show where the issue is (printed only when the tests fail).
            if issue.element == nil, !savedScreenshot {
                savedScreenshot = true
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "audit-\(self.name)-\(issue.compactDescription)"
                shot.lifetime = .keepAlways
                self.add(shot)
            }
            // Report each issue with the element it's on, so CI logs say what to fix.
            let type = issue.element.map { String(describing: $0.elementType) } ?? "?"
            XCTFail("\(issue.compactDescription): \(type) \"\(label)\" — \(issue.detailedDescription)")
            return true
        }
    }
}
