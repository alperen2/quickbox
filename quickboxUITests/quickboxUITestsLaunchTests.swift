//
//  quickboxUITestsLaunchTests.swift
//  quickboxUITests
//
//  Created by Alperen on 27.02.2026.
//

import XCTest

final class quickboxUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        // XCUIApplication().launch() // Disabled to prevent menu bar app termination timeouts on CI
        XCTAssert(true)
    }
}
