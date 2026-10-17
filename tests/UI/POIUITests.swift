import XCTest

final class POIUITests: XCTestCase {
    private func launch(prices: Bool, mode: String = "car", stationary: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_CAR_PREVIEW"] = "1"
        if prices { app.launchEnvironment["BIKENAVI_POI_PREVIEW"] = "1" }
        app.launchEnvironment["BIKENAVI_POI_MODE"] = mode
        if stationary { app.launchEnvironment["BIKENAVI_CAR_STATIONARY_PREVIEW"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["homeMode_car"].waitForExistence(timeout: 20))
        let tile = app.buttons["homeMode_" + mode]
        for _ in 0..<4 where !tile.isHittable { app.swipeUp() }
        tile.tap()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testPOIsInEveryNonCarModeInPlanningAndDuringRecording() {
        for mode in ["cycling", "hiking", "bikeAndHike", "sea"] {
            let app = launch(prices: true, mode: mode)
            XCTAssertTrue(app.buttons["planningPOIs"].waitForExistence(timeout: 10))
            if mode == "cycling" { capture(app, "83-fahrrad-poi-einstieg") }
            app.buttons["planningPOIs"].tap()
            for category in ["fuel", "supermarket", "airport", "station", "beach", "parking"] {
                XCTAssertTrue(app.buttons["poiCategory_" + category].waitForExistence(timeout: 5))
            }
            app.buttons["poiCategory_supermarket"].tap()
            XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["poiDistanceHint"].label.contains("Luftlinie"))
            if mode == "hiking" { capture(app, "84-wandern-poi-umkreis") }
            app.buttons["poiResult_example-0"].tap()
            XCTAssertTrue(app.buttons["poiSavePlace"].waitForExistence(timeout: 10))
            if mode == "sea" {
                XCTAssertTrue(app.staticTexts["poiLandWarning"].exists)
                XCTAssertFalse(app.buttons["poiSetDestination"].exists)
            } else {
                XCTAssertTrue(app.buttons["poiSetDestination"].exists)
                XCTAssertTrue(app.buttons["poiAddToPlan"].exists)
            }
            app.buttons["Zurück"].tap()
            app.buttons["Fertig"].tap()
            app.tabBars.buttons[mode == "hiking" ? "Gehen" : mode == "sea" ? "Segeln" : "Fahren"].tap()
            XCTAssertTrue(app.buttons["ridePOIs"].waitForExistence(timeout: 15))
            app.buttons["ridePOIs"].tap()
            app.buttons["poiCategory_supermarket"].tap()
            XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
            app.buttons["poiResult_example-0"].tap()
            XCTAssertTrue(app.buttons["poiSavePlace"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["poiAddToRide"].exists)
            XCTAssertFalse(app.buttons["poiSetDestination"].exists)
            for _ in 0..<4 where !app.buttons["poiSavePlace"].isHittable { app.swipeUp() }
            app.buttons["poiSavePlace"].tap()
            XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 5))
            app.buttons["Speichern"].tap()
            app.buttons["Zurück"].tap()
            app.buttons["Fertig"].tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
            if mode == "hiking" { capture(app, "86-wandern-poi-unterwegs") }
            app.terminate()
        }
    }
    func testAllCategoriesAndMissingServerAndRideReturn() {
        let app = launch(prices: false)
        Thread.sleep(forTimeInterval: 5)
        capture(app, "68-auto-planung")
        app.buttons["planningPOIs"].tap()
        for category in ["fuel", "supermarket", "airport", "station", "beach", "parking"] {
            XCTAssertTrue(app.buttons["poiCategory_" + category].waitForExistence(timeout: 5))
        }
        capture(app, "79-auto-poi-kacheln")
        app.buttons["poiCategory_fuel"].tap()
        XCTAssertTrue(app.staticTexts["poiError"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["ridePOIs"].waitForExistence(timeout: 15))
        capture(app, "70-auto-fahren")
        app.buttons["ridePOIs"].tap()
        XCTAssertTrue(app.buttons["poiCategory_fuel"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["carPause"].waitForExistence(timeout: 5))
    }

    func testMarineLandPlaceCanBeSavedWithoutChangingWaterRoute() {
        let app = launch(prices: true, mode: "sea")
        app.buttons["planningPOIs"].tap()
        app.buttons["poiCategory_supermarket"].tap()
        XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
        app.buttons["poiResult_example-0"].tap()
        XCTAssertTrue(app.staticTexts["poiLandWarning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["poiSavePlace"].exists)
        XCTAssertFalse(app.buttons["poiSetDestination"].exists)
        Thread.sleep(forTimeInterval: 8)
        capture(app, "85-segeln-poi-landgang")
    }

    func testClayGridRemainsReachableOnSmallScreens() {
        let app = launch(prices: false)
        app.buttons["planningPOIs"].tap()
        for category in ["fuel", "supermarket", "airport", "station", "beach", "parking"] {
            let tile = app.buttons["poiCategory_" + category]
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            for _ in 0..<4 where !tile.isHittable { app.swipeUp() }
            XCTAssertTrue(tile.isHittable)
        }
        app.buttons["poiCategory_parking"].tap()
        XCTAssertTrue(app.staticTexts["poiError"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["planningPOIs"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testDieselResultsDetailsAndPlanInsertion() async throws {
        let (_, response) = try await URLSession.shared.data(from: URL(string: "https://127.0.0.1:18446/health")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let app = launch(prices: true)
        app.buttons["planningPOIs"].tap()
        app.buttons["poiCategory_fuel"].tap()
        XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["poiResult_example-1"].exists)
        capture(app, "80-auto-diesel-angebote")
        app.buttons["poiResult_example-0"].tap()
        XCTAssertTrue(app.buttons["poiSetDestination"].waitForExistence(timeout: 10))
        for _ in 0..<4 where !app.buttons["poiAddToPlan"].isHittable { app.swipeUp() }
        app.buttons["poiAddToPlan"].tap()
        XCTAssertTrue(app.buttons["planningPOIs"].waitForExistence(timeout: 5))
        app.buttons["planningPOIs"].tap()
        XCTAssertTrue(app.buttons["poiCategory_parking"].waitForExistence(timeout: 5))
        app.buttons["poiCategory_parking"].tap()
        XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
    }

    func testStationaryCarKeepsGPSAndCanSelectSupermarket() {
        let app = launch(prices: true, stationary: true)
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["ridePOIs"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 7)
        XCTAssertFalse(app.staticTexts["GPS-Signal fehlt"].exists)
        capture(app, "89-auto-stillstand")
        app.buttons["ridePOIs"].tap()
        app.buttons["poiCategory_supermarket"].tap()
        XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
        capture(app, "90-auto-poi-stillstand")
        app.buttons["poiResult_example-0"].tap()
        XCTAssertTrue(app.buttons["poiAddToRide"].waitForExistence(timeout: 10))
        for _ in 0..<4 where !app.buttons["poiAddToRide"].isHittable { app.swipeUp() }
        app.buttons["poiAddToRide"].tap()
        XCTAssertTrue(app.buttons["removePOIStop"].waitForExistence(timeout: 10))
        let returnedToRide = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["removePOIStop"])
        XCTAssertEqual(XCTWaiter.wait(for: [returnedToRide], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["poiAddToRide"].exists)
        XCTAssertTrue(app.buttons["carPause"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["carPause"].label, "Pause")
        XCTAssertFalse(app.staticTexts["GPS-Signal fehlt"].exists)
    }

    func testDieselSearchAlongRouteKeepsRecording() {
        let app = launch(prices: true)
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["ridePOIs"].waitForExistence(timeout: 15))
        app.buttons["ridePOIs"].tap()
        app.buttons["poiCategory_fuel"].tap()
        XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Beispiel · entlang der Route"].exists)
        capture(app, "81-auto-diesel-route")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["carPause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["carPause"].label, "Pause")
    }

    func testOtherCategoriesShowArrivalWarningAndAllowPlanning() {
        let app = launch(prices: true)
        app.buttons["planningPOIs"].tap()
        for category in ["supermarket", "airport", "beach", "parking", "station"] {
            let tile = app.buttons["poiCategory_" + category]
            for _ in 0..<4 where !tile.isHittable { app.swipeUp() }
            tile.tap()
            XCTAssertTrue(app.buttons["poiResult_example-0"].waitForExistence(timeout: 10))
            app.buttons["poiResult_example-0"].tap()
            XCTAssertTrue(app.buttons["poiSetDestination"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "125 m Luftlinie")).firstMatch.exists)
            if category == "station" {
                Thread.sleep(forTimeInterval: 5)
                capture(app, "82-auto-poi-zielpunkt")
                for _ in 0..<4 where !app.buttons["poiAddToPlan"].isHittable { app.swipeUp() }
                app.buttons["poiAddToPlan"].tap()
                XCTAssertTrue(app.buttons["planningPOIs"].waitForExistence(timeout: 5))
            } else {
                app.buttons["Zurück"].tap()
                app.buttons["Kategorien"].tap()
            }
        }
    }
}
