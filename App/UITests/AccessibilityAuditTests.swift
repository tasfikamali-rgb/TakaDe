import XCTest

/// Runs Apple's built-in accessibility audit (the same checks as Accessibility
/// Inspector: contrast, element labels, hit-target size, Dynamic Type, clipped
/// text, traits) on the main screens, plus a crash-free launch at the largest
/// text size. App Review flags apps that are unusable with VoiceOver or large text.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testGroupsScreen() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["No groups yet"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testNewGroupSheet() throws {
        let app = launch()
        app.buttons["Create a group"].tap()
        XCTAssertTrue(app.navigationBars["New group"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testProfileScreen() throws {
        let app = launch()
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Profile"].firstMatch.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testLargestTextSizeLaunches() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.staticTexts["No groups yet"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
    }

    @MainActor
    func testBengaliLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguage", "bn", "-AppleLanguages", "(bn)", "-AppleLocale", "bn_BD"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription])
    }

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
}
