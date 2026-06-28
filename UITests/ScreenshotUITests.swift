import XCTest

/// Captures the App Store screenshot set for one language. The language/region
/// is chosen by the test runner via `xcodebuild -testLanguage/-testRegion`
/// (see `scripts/screenshots.sh`); the app seeds matching demo data on launch.
///
/// Each shot is attached to the test result with a stable name (`01_…`, `02_…`)
/// and `.keepAlways` lifetime; the script exports and renames them afterwards.
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestScreenshots", "1", "-UITestProUnlocked", "1"]
        app.launch()

        // 1 — Watchlist (home)
        let firstCalc = app.buttons["watchlistRow.calc"].firstMatch
        XCTAssertTrue(firstCalc.waitForExistence(timeout: 20), "watchlist did not load")
        capture(app, "01_watchlist")

        // 2 — Position sizing calculator (pre-filled result)
        firstCalc.tap()
        // Give the pushed screen + result card a beat to settle.
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        capture(app, "02_position_sizing")
        goBack(app)

        // 3 — Averaging calculator
        let firstAveraging = app.buttons["watchlistRow.averaging"].firstMatch
        XCTAssertTrue(firstAveraging.waitForExistence(timeout: 10))
        firstAveraging.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        capture(app, "03_averaging")
        goBack(app)
    }

    // MARK: - Helpers

    /// Full-screen, device-resolution screenshot (App Store wants the whole frame,
    /// including the status bar, which the script overrides to a clean 9:41).
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pop the current screen via the navigation bar's leading (back) button.
    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        sleep(1)
    }
}
