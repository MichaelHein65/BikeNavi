import XCTest

final class HomeUITests: XCTestCase {
    private func app() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_CAR_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["homeMode_car"].waitForExistence(timeout: 20))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func assertAllTilesFit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for mode in ["cycling", "car", "hiking", "bikeAndHike", "sea"] {
            let tile = app.buttons["homeMode_" + mode]
            XCTAssertTrue(tile.isHittable, mode, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.frame.minY, 40, mode, file: file, line: line)
            XCTAssertLessThanOrEqual(tile.frame.maxY, app.frame.maxY - 20, mode, file: file, line: line)
        }
        XCTAssertFalse(app.scrollViews.firstMatch.exists, file: file, line: line)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testColorfulHomeAndAllFiveApplicationsHaveDedicatedOptions() {
        let app = app()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        for mode in ["cycling", "car", "hiking", "bikeAndHike", "sea"] { XCTAssertTrue(app.buttons["homeMode_" + mode].exists) }
        assertAllTilesFit(app)
        capture(app, "72-start-clay")
        for (mode, title, image) in [("cycling", "Fahrrad", "06-profil"), ("car", "Auto", "69-Auto-Profil"),
                                     ("hiking", "Wandern", "17-wandern-profil"),
                                     ("bikeAndHike", "Fahrrad & Wandern", "73-rad-wandern-profil"),
                                     ("sea", "Segeln", "57-seeweg-profil")] {
            let tile = app.buttons["homeMode_" + mode]; reveal(tile, app: app); tile.tap()
            XCTAssertTrue(app.staticTexts["applicationTitle"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["applicationTitle"].label, title)
            if !app.buttons["routeProfile"].exists { app.buttons["togglePlanningDetails"].tap() }
            app.buttons["routeProfile"].tap()
            XCTAssertTrue(app.staticTexts["selectedApplicationProfile"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["selectedApplicationProfile"].label, title)
            XCTAssertFalse(app.buttons["travelMode_car"].exists)
            XCTAssertEqual(app.staticTexts["Dein Fahrrad"].exists, mode == "cycling" || mode == "bikeAndHike")
            XCTAssertEqual(app.switches["carAvoidHighways"].exists, mode == "car")
            XCTAssertEqual(app.textFields["profileBoatDraft"].exists, mode == "sea")
            if mode == "hiking" { XCTAssertFalse(app.switches["Elektrische Unterstützung"].exists) }
            capture(app, image)
            app.buttons["Übernehmen"].tap()
            if app.alerts.firstMatch.waitForExistence(timeout: 1) { app.alerts.buttons["Verstanden"].tap() }
            if mode == "hiking" { XCTAssertEqual(app.buttons["mapStyleMenu"].value as? String, "Topografisch") }
            if mode == "sea" { XCTAssertEqual(app.buttons["mapStyleMenu"].value as? String, "Seekarte · OpenSeaMap") }
            app.buttons["returnHome"].tap()
            XCTAssertTrue(app.buttons["homeMode_car"].waitForExistence(timeout: 5))
        }
    }
    func testHomeResumeAndConflictingApplicationNeverReplaceRunningRide() {
        let app = app()
        app.buttons["homeMode_car"].tap()
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["carPause"].waitForExistence(timeout: 10))
        app.buttons["returnHome"].tap()
        XCTAssertTrue(app.buttons["homeResumeRide"].waitForExistence(timeout: 5))
        assertAllTilesFit(app)
        capture(app, "74-start-fortsetzen")
        let hike = app.buttons["homeMode_hiking"]; reveal(hike, app: app); hike.tap()
        app.tabBars.buttons["Gehen"].tap()
        XCTAssertTrue(app.buttons["resumeConflictingRide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["carPause"].exists)
        app.buttons["resumeConflictingRide"].tap()
        XCTAssertEqual(app.staticTexts["applicationTitle"].label, "Auto")
        XCTAssertTrue(app.buttons["carPause"].waitForExistence(timeout: 5))
        app.buttons["carPause"].tap()
        XCTAssertTrue(app.staticTexts["Autofahrt pausiert"].waitForExistence(timeout: 5))
        app.buttons["returnHome"].tap()
        app.buttons["homeResumeRide"].tap()
        XCTAssertTrue(app.staticTexts["Autofahrt pausiert"].waitForExistence(timeout: 5))
        app.buttons["Autofahrt beenden"].tap()
        app.buttons["Speichern und beenden"].tap()
    }
    func testLargeTextHomeKeepsEveryApplicationReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["BIKENAVI_CAR_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["homeMode_cycling"].waitForExistence(timeout: 20))
        assertAllTilesFit(app)
        capture(app, "75-start-grosse-schrift")
        app.buttons["homeMode_sea"].tap()
        XCTAssertTrue(app.staticTexts["applicationTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["applicationTitle"].label, "Segeln")
    }

    func testHikingRideUsesWalkingMetricsWithoutBikeConnection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_START_LOCATION_TEST"] = "delayed"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["homeMode_hiking"].waitForExistence(timeout: 20))
        app.buttons["homeMode_hiking"].tap()
        app.tabBars.buttons["Gehen"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gehzeit"].exists)
        XCTAssertTrue(app.staticTexts["Gegangen"].exists)
        XCTAssertFalse(app.buttons["bikeConnection"].exists)
        XCTAssertTrue(app.staticTexts["Freie Wanderung"].exists)
        capture(app, "76-wandern-unterwegs")
        app.buttons["Tour beenden"].tap()
        app.buttons["Speichern und beenden"].tap()
    }

}
