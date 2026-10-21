import XCTest

final class GPXUITests: XCTestCase {
    func testPreviewImportReverseEditAndFilePicker() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_GPX_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.navigationBars["GPX importieren"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.switches["gpxReverse"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "GPX-Import-Beispiel"; preview.lifetime = .keepAlways; add(preview)
        app.swipeUp()
        let confirm = app.buttons["gpxConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        if !confirm.isHittable { app.swipeUp() }
        let selection = XCTAttachment(screenshot: app.screenshot())
        selection.name = "GPX-Auswahl-Beispiel"; selection.lifetime = .keepAlways; add(selection)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["gpxOriginalTrack"].waitForExistence(timeout: 10))
        app.buttons["gpxReversePlan"].tap()
        XCTAssertTrue(app.buttons["gpxFollow"].exists)
        let plan = XCTAttachment(screenshot: app.screenshot())
        plan.name = "GPX-Originalspur-Beispiel"; plan.lifetime = .keepAlways; add(plan)
        app.buttons["gpxEdit"].tap()
        XCTAssertTrue(app.navigationBars["GPX importieren"].waitForExistence(timeout: 10))
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.staticTexts["gpxOriginalTrack"].waitForExistence(timeout: 10))
        app.buttons["gpxImport"].tap()
        // The system picker itself may use the simulator's configured locale.
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gpxConfirm"].exists)
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "GPX-Dateiauswahl"; picker.lifetime = .keepAlways; add(picker)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["gpxOriginalTrack"].waitForExistence(timeout: 5))
    }
}
