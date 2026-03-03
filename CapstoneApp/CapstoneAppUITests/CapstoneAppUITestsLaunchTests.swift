//
//  CapstoneAppUITestsLaunchTests.swift
//  CapstoneAppUITests
//
//

import XCTest

final class CapstoneAppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let targetBundleID = "com.SipBuddyInc.SipBuddy"

    private func ensureUITestTargetOrSkip() throws {
        // Ensure we're running from the UI tests runner target, not the unit test bundle
        guard Bundle.main.bundleIdentifier?.contains("UITests") == true else {
            throw XCTSkip("Skipping UI launch test when not running from the UITests target.")
        }
    }

    @MainActor
    func testLaunch() throws {
        try ensureUITestTargetOrSkip()

        let app = XCUIApplication(bundleIdentifier: targetBundleID)
        app.launchArguments += ["-UITests"]
        app.launch()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
