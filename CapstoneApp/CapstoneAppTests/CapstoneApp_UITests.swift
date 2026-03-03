//
//  CapstoneApp_UITests.swift
//  CapstoneAppUITests
//
//  UI tests for authentication flows: account creation and login.
//  These tests require a configured Firebase project.
//

import XCTest

final class CapstoneApp_UITests: XCTestCase {

    private let targetBundleID = "com.SipBuddyInc.SipBuddy"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Ensure we're running from the UI tests runner target; otherwise skip to avoid configuration errors.
        guard Bundle.main.bundleIdentifier?.contains("UITests") == true else {
            throw XCTSkip("Skipping UI tests when not running from the UITests target.")
        }

        app = XCUIApplication(bundleIdentifier: targetBundleID)
        app.launchArguments += ["-UITests"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Sign Up Flow
    func testCreateAccountFlow() throws {
        // Expect to be on LoginView initially
        let emailField = app.textFields["Email"]
        let passwordField = app.textFields["Password"]
        let createButton = app.buttons["Create Account"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Email field not found")
        XCTAssertTrue(passwordField.exists, "Password field not found")
        XCTAssertTrue(createButton.exists, "Create Account button not found")

        // Use a unique email so we can create a fresh account per run
        let uniqueEmail = "ui+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Test123456!" // Firebase rules usually require 6+ chars

        emailField.tap()
        emailField.typeText(uniqueEmail)

        passwordField.tap()
        passwordField.typeText(password)

        createButton.tap()

        // After sign-up, AuthWrapperView should briefly show WelcomeScreen
        let welcomeText = app.staticTexts["Welcome to"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 20), "Welcome screen did not appear after account creation")
    }

    // MARK: - Login Flow (skips if env vars not provided)
    func testLoginFlowWithProvidedCredentials() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["UITestEmail"], let password = env["UITestPassword"], !email.isEmpty, !password.isEmpty else {
            throw XCTSkip("UITestEmail and UITestPassword environment variables are not set; skipping login test.")
        }

        let emailField = app.textFields["Email"]
        let passwordField = app.textFields["Password"]
        let loginButton = app.buttons["Login"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Email field not found")
        XCTAssertTrue(passwordField.exists, "Password field not found")
        XCTAssertTrue(loginButton.exists, "Login button not found")

        emailField.tap()
        emailField.typeText(email)

        passwordField.tap()
        passwordField.typeText(password)

        loginButton.tap()

        // Expect the welcome screen to appear on successful auth
        let welcomeText = app.staticTexts["Welcome to"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 20), "Welcome screen did not appear after login")
    }
}
