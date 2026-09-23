import XCTest
import CoreLocation

final class PlannerUITests: XCTestCase {
    func testMapOffersExplicitStartAndDestinationAndEnablesRoutingWithoutGPS() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["Neue Tour"].waitForExistence(timeout: 15))
        app.buttons["Neue Tour"].tap()
        if !app.buttons["waypoints"].exists { app.buttons["togglePlanningDetails"].tap() }
        let map = app.descendants(matching: .any).matching(identifier: "planningMap").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.80)).tap()
        XCTAssertTrue(app.buttons["Als Start verwenden"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Als Ziel verwenden"].exists)
        app.buttons["Als Start verwenden"].tap()
        let calculate = app.buttons["calculateRoute"]
        XCTAssertTrue(calculate.waitForExistence(timeout: 5))
        XCTAssertFalse(calculate.isEnabled)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.70)).tap()
        XCTAssertTrue(app.buttons["Als Ziel verwenden"].waitForExistence(timeout: 5))
        app.buttons["Als Ziel verwenden"].tap()
        // Selecting the destination starts automatically, including without a server client.
        // No cached map exists here, so the automatic calculation reports missing map data.
        XCTAssertTrue(app.alerts.buttons["Verstanden"].waitForExistence(timeout: 5))
        app.alerts.buttons["Verstanden"].tap()
        XCTAssertTrue(calculate.isEnabled)
        attach(app, name: "Planung-Start-Ziel")
    }

    func testResetThenDestinationStartsFromStationaryCurrentLocation() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude:49.4100,longitude:8.7000))
        defer { XCUIDevice.shared.location = nil }
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["Planung zurücksetzen"].waitForExistence(timeout:15))
        // The simulator has a fixed, authorized location. Let the original fix
        // age beyond the planning freshness window without moving five metres.
        let stationary = expectation(description:"Stationary for 18 seconds")
        DispatchQueue.main.asyncAfter(deadline:.now()+18) { stationary.fulfill() }
        wait(for:[stationary],timeout:20)
        app.buttons["Planung zurücksetzen"].tap()
        if !app.buttons["waypoints"].exists { app.buttons["togglePlanningDetails"].tap() }
        let map = app.descendants(matching:.any).matching(identifier:"planningMap").firstMatch
        map.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.65)).tap()
        XCTAssertTrue(app.buttons["Als Ziel verwenden"].waitForExistence(timeout:5))
        app.buttons["Als Ziel verwenden"].tap()
        // With no map cache/client, a missing-data error proves the calculation
        // was actually entered; merely enabling the button is not enough.
        guard app.alerts.buttons["Verstanden"].waitForExistence(timeout:15) else {
            XCTFail("Destination did not start route calculation from GPS"); return
        }
        app.alerts.buttons["Verstanden"].tap()
        XCTAssertTrue(app.staticTexts["Mein Standort"].exists)
        XCTAssertFalse(app.staticTexts["automaticStartStatus"].exists)
        attach(app,name:"Ziel-nach-Zuruecksetzen")
    }

    func testRideBikeDisplaysAndConnectionDetailsShareTheRideScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Fahren"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Fahren"].tap()
        if app.alerts.buttons["Verstanden"].waitForExistence(timeout: 2) {
            app.alerts.buttons["Verstanden"].tap()
        }
        let connection = app.buttons["bikeConnection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 8))
        for id in ["bikeBattery", "bikeMode", "bikeRiderPower", "bikeMotorPower"] {
            let metric = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(metric.exists)
            // An unavailable real bike must never appear as an invented 0 W / 0% sample.
            XCTAssertEqual(metric.value as? String, "Nicht verfügbar")
        }
        attach(app, name: "Fahren-Bike-Anzeigen")
        connection.tap()
        XCTAssertTrue(app.navigationBars["Bike-Verbindung"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        XCTAssertTrue(connection.isHittable)
        app.tabBars.buttons["Einstellungen"].tap()
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
    }

    func testSwipeCollapsesToTitleAndExpandsAgainWithoutChangingThePlan() {
        let app = XCUIApplication()
        // The simulator fixture stays local; these interaction tests never contact the Pi.
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        let toggle = app.buttons["togglePlanningDetails"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let waypoints = app.buttons["waypoints"]
        if !waypoints.exists { toggle.tap() }
        XCTAssertTrue(waypoints.waitForExistence(timeout: 5))
        let title = app.textFields["tourName"]
        let originalTitle = title.value as? String
        let expandedY = title.frame.minY

        let start = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))
        XCTAssertTrue(waitUntil { !waypoints.exists })
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.value as? String, originalTitle)
        XCTAssertGreaterThan(title.frame.minY, expandedY + 100)
        attach(app, name: "Planung-eingeklappt")

        let bottom = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bottom.press(forDuration: 0.05, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(waypoints.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, originalTitle)
        attach(app, name: "Planung-ausgeklappt")

        // The visible arrow provides the same behavior without requiring a swipe.
        toggle.tap()
        XCTAssertTrue(waitUntil { !waypoints.exists })
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["waypoints"].exists)
        app.buttons["togglePlanningDetails"].tap()
        XCTAssertTrue(app.buttons["waypoints"].waitForExistence(timeout: 5))
    }

    func testSavedPlaceActionsStayIndependentAndDeletionRequiresConfirmation() {
        let app = XCUIApplication()
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["Planung zurücksetzen"].waitForExistence(timeout: 15))
        app.buttons["Planung zurücksetzen"].tap()
        let name = "Ort-Test-" + UUID().uuidString.prefix(8)
        let map = app.descendants(matching: .any).matching(identifier: "planningMap").firstMatch
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["Ort speichern"].waitForExistence(timeout: 5))
        app.buttons["Ort speichern"].tap()
        let field = app.textFields["Zum Beispiel: Lieblingscafé"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Speichern"].tap()

        // Check both entry points, including persistence after selecting the place.
        for entry in ["Meine gespeicherten Orte", "placeSearch"] {
            app.buttons[entry].tap()
            let cell = app.cells.containing(.button, identifier: name).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.buttons["Gespeicherten Ort umbenennen"].tap()
            XCTAssertTrue(app.textFields["Zum Beispiel: Lieblingscafé"].waitForExistence(timeout: 5))
            app.buttons["Abbrechen"].tap()
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.buttons["Gespeicherten Ort löschen"].tap()
            XCTAssertTrue(app.buttons["Ort löschen"].waitForExistence(timeout: 5))
            if app.buttons["Abbrechen"].exists {
                app.buttons["Abbrechen"].tap()
            } else {
                // iOS 26 presents this as a popover with an outside-dismiss region.
                app.otherElements["PopoverDismissRegion"]
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
            }
            XCTAssertTrue(waitUntil { !app.buttons["Ort löschen"].exists })
            XCTAssertTrue(cell.exists)
            cell.buttons[name].tap()
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 5))
            if app.alerts.buttons["Verstanden"].waitForExistence(timeout: 2) {
                app.alerts.buttons["Verstanden"].tap()
            }
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 15))
            app.buttons[entry].tap()
            XCTAssertTrue(app.cells.containing(.button, identifier: name).firstMatch.waitForExistence(timeout: 5))
            app.buttons["Fertig"].tap()
            app.buttons["Planung zurücksetzen"].tap()
        }
        app.buttons["Meine gespeicherten Orte"].tap()
        let cell = app.cells.containing(.button, identifier: name).firstMatch
        cell.buttons["Gespeicherten Ort löschen"].tap()
        app.buttons["Ort löschen"].tap()
        XCTAssertTrue(waitUntil { !cell.exists })
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Meine gespeicherten Orte"].waitForExistence(timeout: 15))
        app.buttons["Meine gespeicherten Orte"].tap()
        XCTAssertFalse(app.cells.containing(.button, identifier: name).firstMatch.exists)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Run after scripts/seed_gallery.py on a dedicated simulator; otherwise skipped.
final class DocumentationScreenshotsTests: XCTestCase {
    func testCaptureGallery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(coordinate: .init(latitude: 49.414601, longitude: 8.681496), altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5, course: 90, speed: 0, timestamp: Date()))
        defer { XCUIDevice.shared.location = nil }
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 20))
        guard app.textFields["tourName"].value as? String == "Heidelberg · Beispieltour" else {
            throw XCTSkip("Seed the documentation simulator with scripts/seed_gallery.py first.")
        }
        if !app.buttons["waypoints"].exists { app.buttons["togglePlanningDetails"].tap() }
        capture(app, "01-planen", delay: 12)
        app.buttons["togglePlanningDetails"].tap()
        capture(app, "02-karte")
        app.buttons["togglePlanningDetails"].tap()
        app.buttons["waypoints"].tap()
        capture(app, "03-wegpunkte")
        app.buttons["Fertig"].tap()
        app.buttons["Meine gespeicherten Orte"].tap()
        capture(app, "04-orte")
        app.buttons["Fertig"].tap()
        app.buttons["placeSearch"].tap()
        capture(app, "05-suche")
        app.buttons["Fertig"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tourenrad")).firstMatch.tap()
        capture(app, "06-profil")
        // Reopen without applying a new profile or recalculating the offline fixture.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Höhenprofil und Wegbeläge"].waitForExistence(timeout: 15))
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        XCTAssertTrue(app.navigationBars["Deine Strecke"].waitForExistence(timeout: 5))
        capture(app, "07-routendetails")
        app.buttons["Fertig"].tap()
        app.tabBars.buttons["Touren"].tap()
        capture(app, "08-touren")
        app.buttons["Gefahren"].tap()
        app.staticTexts["Heidelberg · Beispielaufzeichnung"].tap()
        capture(app, "09-fahrtdetails")
        app.swipeUp()
        capture(app, "10-auswertung")
        app.tabBars.buttons["Einstellungen"].tap()
        capture(app, "11-einstellungen")
    }

    func testCaptureRideScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launchEnvironment["BIKENAVI_PREVIEW_LOCATION"] = "49.414601,8.681496"
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 49.414601, longitude: 8.681496))
        defer { XCUIDevice.shared.location = nil }
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 20))
        guard app.textFields["tourName"].value as? String == "Heidelberg · Beispieltour" else {
            throw XCTSkip("Seed the documentation simulator first.")
        }
        app.tabBars.buttons["Fahren"].tap()
        let allowLocation = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Beim Verwenden der App erlauben"]
        if allowLocation.waitForExistence(timeout: 3) { allowLocation.tap() }
        if app.alerts.buttons["Verstanden"].waitForExistence(timeout: 3) {
            app.alerts.buttons["Verstanden"].tap()
            XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 49.414601, longitude: 8.681496))
            app.tabBars.buttons["Planen"].tap()
            app.buttons["Tour starten"].tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 15))
        capture(app, "12-fahren", delay: 5)
        app.buttons["bikeConnection"].tap()
        capture(app, "13-bike")
        app.buttons["Fertig"].tap()
        app.buttons["Pause"].tap()
        capture(app, "14-pause")
    }

    private func capture(_ app: XCUIApplication, _ name: String, delay: TimeInterval = 1) {
        let ready = expectation(description: "Wait for the actual screen to settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { ready.fulfill() }
        wait(for: [ready], timeout: delay + 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
