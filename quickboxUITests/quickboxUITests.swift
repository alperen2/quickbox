import XCTest

final class quickboxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAutocompleteSupportsMouseSelectionForTagAndProject() throws {
        let app = launchHostApp()
        let input = app.textFields["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.click()
        input.typeText("#")

        let firstItem = app.buttons["autocomplete-item-0"]
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3))
        firstItem.click()

        let tagValue = (input.value as? String) ?? ""
        XCTAssertTrue(tagValue.contains("#deepwork "))

        input.typeText("@")
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3))
        firstItem.click()

        let projectValue = (input.value as? String) ?? ""
        XCTAssertTrue(projectValue.contains("@ProjectAlpha "))
    }

    @MainActor
    func testMetadataInsightsShowResolvedAndUnresolvedStates() throws {
        let app = launchHostApp()
        let input = app.textFields["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.click()
        input.typeText("due:next friday due:invalidtext")

        let resolvedInsight = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "due:next friday")).firstMatch
        XCTAssertTrue(resolvedInsight.waitForExistence(timeout: 3))

        let unresolvedInsight = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unresolved date")).firstMatch
        XCTAssertTrue(unresolvedInsight.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSuccessfulSubmitShowsToastAndKeepsInputReady() throws {
        let app = launchHostApp()
        let input = app.textFields["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.click()
        input.typeText("UI test capture\r")

        let successToast = app.otherElements["capture-success-toast"]
        XCTAssertTrue(successToast.waitForExistence(timeout: 3))

        input.typeText("a")
        let value = (input.value as? String) ?? ""
        XCTAssertTrue(value.contains("a"))
    }

    @MainActor
    private func launchHostApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-test-host-window"]
        if app.state == .notRunning {
            app.launch()
        } else {
            app.activate()
        }
        return app
    }
}
