import XCTest

/// Drives the App Store preview-video flow at a watchable pace: add a futures
/// contract from search to the watchlist, then size a position and sweep the
/// risk levels so the result updates on screen. `scripts/record_preview.sh`
/// records the simulator screen while this runs.
///
/// Language/region come from the runner (`xcodebuild -testLanguage/-testRegion`)
/// and the app seeds matching demo data (RU → MOEX, EN → CME). We detect which
/// from an on-screen instrument name rather than system locale.
final class PreviewVideoUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testRecordPreview() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestVideo", "1", "-UITestProUnlocked", "1"]
        app.launch()

        // Detect the showcase exchange from a seeded watchlist row (the system
        // chrome language isn't a reliable signal; this content is).
        let isCme = app.staticTexts["Crude Oil WTI"].waitForExistence(timeout: 20)
        let q       = isCme ? "ES"   : "Si"
        let hero    = isCme ? "ESU6" : "Si-9.26"
        let entry   = isCme ? "5600" : "92000"
        let stop    = isCme ? "5594" : "91200"

        sleep(2) // hold on the starting watchlist

        // 1 — Add the hero contract from search.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "no search field")
        search.tap()
        sleep(1)
        search.typeText(q)
        sleep(1)
        let result = app.buttons["searchResult.\(hero)"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "hero not in search results")
        result.tap()
        sleep(3) // the new instrument appears at the top of the watchlist

        // 2 — Size a position on the hero (now the first row).
        let calc = app.buttons["watchlistRow.calc"].firstMatch
        XCTAssertTrue(calc.waitForExistence(timeout: 10))
        calc.tap()
        sleep(1)

        let entryField = app.textFields["calc.entry"]
        XCTAssertTrue(entryField.waitForExistence(timeout: 10))
        entryField.tap()
        entryField.typeText(entry)
        sleep(1)

        let stopField = app.textFields["calc.stop"]
        XCTAssertTrue(stopField.waitForExistence(timeout: 10))
        stopField.tap()
        stopField.typeText(stop)
        sleep(1)

        // Dismiss the keyboard so the result card is visible. Tapping the already-
        // selected first segment ("Buy") resigns the field without changing state
        // and is language-independent.
        let buy = app.segmentedControls.buttons.element(boundBy: 0)
        if buy.exists { buy.tap() }
        sleep(2)

        // 3 — Sweep risk levels; the recommended lots / loss / margin update live.
        tapRisk(app, "2"); sleep(2)
        tapRisk(app, "3"); sleep(2)
        tapRisk(app, "1"); sleep(2)

        // Leave the calculator — this triggers the app's "end" marker so the
        // recorder stops here, keeping the clip bounded to the demo.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    @MainActor
    private func tapRisk(_ app: XCUIApplication, _ percent: String) {
        let chip = app.buttons["risk.preset.\(percent)"].firstMatch
        if chip.waitForExistence(timeout: 5) { chip.tap() }
    }
}
