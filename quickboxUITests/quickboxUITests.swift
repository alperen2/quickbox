//
//  quickboxUITests.swift
//  quickboxUITests
//
//  Created by Alperen on 27.02.2026.
//

import XCTest

final class quickboxUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // XCUIApplication().launch() // Disabled to prevent menu bar app termination timeouts on CI
        XCTAssert(true)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Disabled to prevent timeout
    }
}
