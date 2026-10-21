import XCTest

final class RegionalUITests: XCTestCase {
    func testOfflineViewsRegionsAndPlaces() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_REGION_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["ridePresentation"].waitForExistence(timeout: 30))
        snapshot(app, "Offline-Navigation-Beispiel")
        app.buttons["ridePresentation"].tap()
        app.buttons["E-Bike-Technik"].tap()
        XCTAssertTrue(app.staticTexts["energyEstimate"].waitForExistence(timeout: 15))
        app.scrollViews["rideInformation"].swipeUp()
        snapshot(app, "E-Bike-Technik-Beispiel")
        // Restore the menu into the visible part of the lower scroll view.
        app.scrollViews["rideInformation"].swipeDown()
        app.buttons["ridePresentation"].tap()
        app.buttons["Touristik"].tap()
        XCTAssertTrue(app.buttons["rideOfflinePlaces"].waitForExistence(timeout: 5))
        snapshot(app, "Touristik-Beispiel")
        app.buttons["rideOfflinePlaces"].tap()
        XCTAssertTrue(app.navigationBars["Offline-Regionen"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.buttons["useRegion"].exists)
        snapshot(app, "Offline-Region-Beispiel")
        app.buttons["Offline-Orte"].tap()
        XCTAssertTrue(app.staticTexts["Beispieldaten · Trinkbrunnen"].waitForExistence(timeout: 10))
        snapshot(app, "Offline-Orte-Beispiel")
        app.buttons["Ort merken"].tap()
        XCTAssertTrue(app.staticTexts["Ort gespeichert"].waitForExistence(timeout: 5))
    }
    func testRouteQualityAndPreferences() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_REGION_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["ridePresentation"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Planen"].tap()
        if !app.buttons["routeProfile"].isHittable { app.buttons["togglePlanningDetails"].tap() }
        app.buttons["routeProfile"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Routenvariante"].exists)
        snapshot(app, "Routenvarianten-Beispiel")
        app.buttons["Übernehmen"].tap()
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        for _ in 0..<4 { if app.buttons["Abschnitte und Datenquelle"].isHittable { break }; app.swipeUp() }
        app.buttons["Abschnitte und Datenquelle"].tap()
        XCTAssertTrue(app.navigationBars["Wegeabschnitte"].waitForExistence(timeout: 5))
        snapshot(app, "Wegequalitaet-Beispiel")
    }
    func testPrereleaseSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_REGION_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["ridePresentation"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Einstellungen"].tap()
        for _ in 0..<8 { if app.staticTexts["prereleaseVersion"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["prereleaseVersion"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "0.5.0 (5)", "0.5.0 (5)")).firstMatch.exists)
        snapshot(app, "Vorabversion-0-5-0-rc1")
    }
    func testAccessibleRideControls() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["BIKENAVI_REGION_PREVIEW"] = "1"
        app.launchEnvironment["BIKENAVI_SERVER"] = ""
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["ridePresentation"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Fortsetzen"].isHittable)
        XCTAssertTrue(app.buttons["Tour beenden"].isHittable)
        app.buttons["ridePresentation"].tap()
        app.buttons["E-Bike-Technik"].tap()
        XCTAssertTrue(app.buttons["Fortsetzen"].isHittable)
        XCTAssertTrue(app.buttons["Tour beenden"].isHittable)
        snapshot(app, "Fahransicht-Grosse-Schrift-Beispiel")
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
