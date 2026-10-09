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
    func testCaptureReleaseVersionSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Einstellungen"].tap()
        capture(app, "11-einstellungen", delay: 1)
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label CONTAINS %@", "0.4.0 (4)", "0.4.0 (4)")).firstMatch
        for _ in 0..<4 { if version.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(version.exists)
        capture(app, "38-version-0-4", delay: 1)
        app.terminate()
    }

    func testBlogHTMLPreviewWithPublicExample() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        app.tabBars.buttons["Touren"].tap()
        app.segmentedControls.buttons["Gefahren"].tap()
        let entry = app.cells.containing(.staticText, identifier: "Heidelberg · Beispielaufzeichnung").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.buttons["generateBlog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["generateBlog"].exists)
        XCTAssertTrue(app.buttons["previewBlog"].isHittable)
        capture(app, "35-tour-blog-direkt", delay: 1)
        for _ in 0..<5 { if app.buttons["openBlogJournal"].isHittable { break }; app.swipeUp() }
        app.buttons["openBlogJournal"].tap()
        let preview = app.buttons["previewBlog"]
        for _ in 0..<5 { if preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable); preview.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews["blogHTMLReady"].waitForExistence(timeout: 45))
        capture(app, "32-blog-vorschau", delay: 1)
        app.webViews.firstMatch.swipeUp()
        let overview = app.webViews.images.matching(NSPredicate(format: "label CONTAINS %@", "Topografische Streckenübersicht")).firstMatch
        for _ in 0..<12 {
            if overview.isHittable && overview.frame.midY < app.webViews.firstMatch.frame.maxY - 120 { break }
            app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.1, thenDragTo: app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        }
        XCTAssertTrue(overview.isHittable)
        capture(app, "33-blog-karte", delay: 1)
        let elevation = app.webViews.images.matching(NSPredicate(format: "label CONTAINS %@", "Höhenprofil: Höhe in Metern")).firstMatch
        for _ in 0..<12 {
            if elevation.isHittable && elevation.frame.midY < app.webViews.firstMatch.frame.maxY - 100 { break }
            app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.1, thenDragTo: app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        }
        XCTAssertTrue(elevation.isHittable)
        capture(app, "37-blog-profilachsen", delay: 1)
        let topo = app.webViews.images.matching(NSPredicate(format: "label CONTAINS %@", "Topografischer Kartenausschnitt")).firstMatch
        for _ in 0..<16 {
            if topo.isHittable && topo.frame.midY < app.webViews.firstMatch.frame.maxY - 160 { break }
            app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.1, thenDragTo: app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        }
        XCTAssertTrue(topo.isHittable)
        capture(app, "34-blog-topografie", delay: 1)
        app.buttons["Fertig"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["Geplant"].tap()
        let planEntry = app.cells.containing(.staticText, identifier: "Heidelberg · Höhenbeispiel").firstMatch
        XCTAssertTrue(planEntry.waitForExistence(timeout: 5)); planEntry.tap()
        XCTAssertTrue(app.buttons["previewBlog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Blog der letzten gefahrenen Tour"].exists)
        capture(app, "36-plan-blog-direkt", delay: 1)
        app.terminate()
    }

    func testBlogStationInsertEditOrderAndOfflineRestart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        func openJournal() {
            app.tabBars.buttons["Touren"].tap()
            app.segmentedControls.buttons["Gefahren"].tap()
            let entry = app.cells.containing(.staticText, identifier: "Heidelberg · Beispielaufzeichnung").firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
            for _ in 0..<5 { if app.buttons["openBlogJournal"].isHittable { break }; app.swipeUp() }
            app.buttons["openBlogJournal"].tap()
        }
        app.launch(); openJournal()
        for _ in 0..<5 { if app.buttons["addBlogPoint"].isHittable { break }; app.swipeUp() }
        capture(app, "31-tourtagebuch")
        app.buttons["addBlogPoint"].tap()
        XCTAssertTrue(app.textFields["blogPointTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveBlogPoint"].isEnabled)
        capture(app, "39-blog-station-hinzufuegen")
        app.buttons["Foto auswählen"].tap()
        let cell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), app.debugDescription)
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let titleReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.textFields["blogPointTitle"])
        XCTAssertEqual(XCTWaiter.wait(for: [titleReady], timeout: 15), .completed)
        let title = app.textFields["blogPointTitle"]
        title.tap(); title.typeText("Foto-Nachtrag · Beispieldaten")
        app.buttons["blogKeyboardDone"].tap()
        XCTAssertTrue(app.buttons["saveBlogPoint"].isEnabled, app.debugDescription)
        let position = app.buttons["blogPointPosition"]
        for _ in 0..<4 { if position.isHittable { break }; app.swipeUp() }
        position.tap()
        app.buttons["2 · Nach Neckarblick · Beispieldaten"].tap()
        capture(app, "40-blog-station-position")
        app.buttons["saveBlogPoint"].tap()
        let inserted = app.staticTexts["2. Foto-Nachtrag · Beispieldaten"]
        for _ in 0..<5 { if inserted.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(inserted.exists)
        app.buttons["editBlogPoint-1"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let old = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Korrigierter Nachtrag · Beispieldaten")
        let note = app.descendants(matching: .any).matching(identifier: "blogPointNote").firstMatch
        note.tap(); note.typeText("Korrigierte synthetische Beispielnotiz.")
        app.buttons["blogKeyboardDone"].tap()
        for _ in 0..<4 { if position.isHittable { break }; app.swipeUp() }
        position.tap(); app.buttons["1 · An den Anfang"].tap()
        capture(app, "41-blog-station-bearbeiten")
        app.buttons["saveBlogPoint"].tap()
        app.terminate(); app.launch(); openJournal()
        let corrected = app.staticTexts["1. Korrigierter Nachtrag · Beispieldaten"]
        for _ in 0..<6 { if corrected.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(corrected.exists)
        XCTAssertTrue(app.staticTexts["Korrigierte synthetische Beispielnotiz."].exists)
        app.terminate()
    }

    func testBlogPointOfflineAndJournalScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launchEnvironment["BIKENAVI_PREVIEW_LOCATION"] = "49.414601,8.681496"
        app.launchEnvironment["BIKENAVI_BLOG_STALE_LOCATION"] = "delayed"
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 20))
        let tourTitle = app.textFields["tourName"].value as? String ?? ""
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["captureBlogPoint"].waitForExistence(timeout: 15))
        capture(app, "12-fahren")
        app.buttons["captureBlogPoint"].tap()
        let title = app.textFields["blogPointTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveBlogPoint"].isEnabled)
        title.tap(); title.typeText("Neckarblick · Beispieldaten")
        let note = app.descendants(matching: .any).matching(identifier: "blogPointNote").firstMatch
        note.tap(); note.typeText("Synthetische Beispielnotiz: Eine kleine Pause am Fluss. Weiter geht es mit frischer Neugier!")
        // Dismiss keyboard so the complete form is visible in the documentation.
        app.buttons["blogKeyboardDone"].tap()
        XCTAssertTrue(app.buttons["saveBlogPoint"].isEnabled)
        capture(app, "30-blog-ort")
        app.buttons["saveBlogPoint"].tap()
        XCTAssertTrue(app.buttons["Tour beenden"].waitForExistence(timeout: 5))
        app.buttons["Tour beenden"].tap()
        app.buttons["Speichern und beenden"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Gefahren"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Gefahren"].tap()
        let entry = app.cells.containing(.staticText, identifier: tourTitle).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["generateBlog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["generateBlog"].isHittable)
        let journal = app.buttons["openBlogJournal"]
        for _ in 0..<5 { if journal.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(journal.isHittable); journal.tap()
        XCTAssertTrue(app.staticTexts["1. Neckarblick · Beispieldaten"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 Ort · 1 zur Übertragung vorgemerkt"].exists)
        capture(app, "31-tourtagebuch")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Touren"].tap()
        app.segmentedControls.buttons["Gefahren"].tap()
        app.cells.containing(.staticText, identifier: tourTitle).firstMatch.tap()
        for _ in 0..<5 { if app.buttons["openBlogJournal"].isHittable { break }; app.swipeUp() }
        app.buttons["openBlogJournal"].tap()
        XCTAssertTrue(app.staticTexts["1. Neckarblick · Beispieldaten"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["generateBlog"].isEnabled)
        app.buttons["generateBlog"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Verbinde den Pi")).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testWaypointSkipLargeButtons() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launchEnvironment["BIKENAVI_PREVIEW_LOCATION"] = "49.414601,8.681496"
        app.launchEnvironment["BIKENAVI_PREVIEW_SKIP"] = "1"
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Fahren"].tap()
        let yes = app.buttons["skipWaypointYes"], no = app.buttons["skipWaypointNo"]
        XCTAssertTrue(yes.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(yes.frame.height, 96)
        XCTAssertGreaterThanOrEqual(no.frame.height, 96)
        XCTAssertTrue(yes.isHittable); XCTAssertTrue(no.isHittable)
        capture(app, "15-zwischenziele", delay: 2)
        no.tap()
        XCTAssertFalse(yes.exists)
        app.buttons["Tour beenden"].tap()
        app.buttons["Speichern und beenden"].tap()
        app.tabBars.buttons["Planen"].tap()
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(yes.waitForExistence(timeout: 10))
        yes.tap()
        XCTAssertFalse(yes.exists)
        XCTAssertTrue(app.buttons["Pause"].exists)
        app.terminate()
    }

    func testCaptureSavedElevationOffline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launch()
        XCTAssertTrue(app.textFields["tourName"].waitForExistence(timeout: 20))
        guard app.textFields["tourName"].value as? String == "Heidelberg · Höhenbeispiel" else {
            throw XCTSkip("Seed the documentation simulator with scripts/seed_gallery.py --elevation first.")
        }
        if !app.buttons["waypoints"].exists { app.buttons["togglePlanningDetails"].tap() }
        capture(app, "01-planen", delay: 12)
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        let source = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Geländehöhen: openrouteservice")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Keine Höhendaten verfügbar"].exists)
        XCTAssertFalse(app.buttons["Höhendaten laden"].exists)
        capture(app, "07-routendetails")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Höhenprofil und Wegbeläge"].waitForExistence(timeout: 15))
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Höhendaten laden"].exists)
    }

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
        guard ["Heidelberg · Beispieltour", "Heidelberg · Höhenbeispiel"].contains(app.textFields["tourName"].value as? String ?? "") else {
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
        // Fresh synthetic movement produces navigation progress and an ETA.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 49.41465, longitude: 8.68160))
        let eta = app.descendants(matching: .any).matching(identifier: "rideETA").firstMatch
        XCTAssertTrue(eta.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ETA"].exists)
        capture(app, "12-fahren", delay: 5)
        app.buttons["bikeConnection"].tap()
        capture(app, "13-bike")
        app.buttons["Fertig"].tap()
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["—"].exists)
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


final class RideLocationTests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_START_LOCATION_TEST"] = scenario
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Fahren"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Fahren"].tap()
        return app
    }
    func testDelayedFixRecoversStaleDenialAndStartsRide() {
        let app = launch("delayed")
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-16-standortsuche"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(app.alerts["BikeNavi"].exists)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 12))
    }
    func testCancelledStartIgnoresLateFix() {
        let app = launch("delayed")
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
        app.buttons["Standortsuche abbrechen"].tap()
        XCTAssertFalse(app.buttons["Pause"].waitForExistence(timeout: 7))
        XCTAssertFalse(app.alerts["BikeNavi"].exists)
    }
    func testMissingFixTimesOutAndCanRetry() {
        let app = launch("timeout")
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts["BikeNavi"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Noch kein aktueller Standort verfügbar. Bitte versuche den Fahrtstart erneut."].exists)
        app.buttons["Verstanden"].tap()
        app.tabBars.buttons["Planen"].tap()
        app.tabBars.buttons["Fahren"].tap()
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
    }
    func testDeniedPermissionExplainsSettings() {
        let app = launch("denied")
        XCTAssertTrue(app.alerts["BikeNavi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bitte erlaube BikeNavi den Standortzugriff in den iPhone-Einstellungen."].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
    }
    func testBackgroundCancelsPendingStart() {
        let app = launch("delayed")
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.buttons["Pause"].waitForExistence(timeout: 7))
        XCTAssertFalse(app.buttons["Standortsuche abbrechen"].exists)
    }
    func testLeavingRideTabCancelsPendingStart() {
        let app = launch("delayed")
        XCTAssertTrue(app.buttons["Standortsuche abbrechen"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Planen"].tap()
        XCTAssertFalse(app.buttons["Pause"].waitForExistence(timeout: 7))
        XCTAssertTrue(app.tabBars.buttons["Planen"].isSelected)
    }
}


final class SettingsVolumeTests: XCTestCase {
    func testSystemVolumeBoxIsFirstAndOffersPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Einstellungen"].tap()
        let label = app.staticTexts["systemVolumeLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertLessThan(label.frame.minY, app.buttons["Speichern und Verbindung prüfen"].frame.minY)
        XCTAssertFalse(app.sliders["speechVolume"].exists)
        XCTAssertTrue(app.buttons["volumePreview"].isHittable)
        app.buttons["volumePreview"].tap()
        app.tabBars.buttons["Planen"].tap()
        app.tabBars.buttons["Einstellungen"].tap()
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        // System volume itself is only available on a physical iPhone.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-11-einstellungen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class CoordinateSearchTests: XCTestCase {
    func testCoordinateSearchWithoutServerAndSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["placeSearch"].waitForExistence(timeout: 15))
        app.buttons["placeSearch"].tap()
        let field = app.textFields["placeSearchQuery"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("49,4100; 8,7000")
        app.buttons["placeSearchSubmit"].tap()
        let result = app.buttons.matching(identifier: "placeSearchResult").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-05-suche"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        result.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        // A previously seeded example plan can start recalculation after inserting the point.
        if app.alerts.buttons["Verstanden"].waitForExistence(timeout: 3) { app.alerts.buttons["Verstanden"].tap() }
        if !app.buttons["waypoints"].exists { app.buttons["togglePlanningDetails"].tap() }
        app.buttons["waypoints"].tap()
        XCTAssertTrue(app.staticTexts["49.410000; 8.700000"].waitForExistence(timeout: 5))
    }
}

final class WalkingOptionsTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launch()
        XCTAssertTrue(app.buttons["togglePlanningDetails"].waitForExistence(timeout:20))
        if !app.buttons["routeProfile"].exists { app.buttons["togglePlanningDetails"].tap() }
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot:app.screenshot())
        attachment.name = "Gallery-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testWalkingModesSelectionAndPersistence() {
        let app = launch()
        app.buttons["routeProfile"].tap()
        for mode in ["cycling", "bikeAndHike", "hiking"] {
            XCTAssertTrue(app.buttons["travelMode_" + mode].waitForExistence(timeout:5))
        }
        capture(app,"06-profil")
        app.buttons["travelMode_bikeAndHike"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Mit dem Rad so nah")).firstMatch.exists)
        app.buttons["travelMode_hiking"].tap()
        XCTAssertFalse(app.switches["Elektrische Unterstützung"].exists)
        capture(app,"17-wandern-profil")
        app.buttons["Übernehmen"].tap()
        XCTAssertTrue(app.buttons["routeProfile"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["routeProfile"].label.contains("Wandern"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["routeProfile"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["routeProfile"].label.contains("Wandern"))
    }
    func testPlanningDistinguishesPreferredAndStrictPaving() {
        let app = launch()
        for (title, image) in [("Befestigte Wege bevorzugen", "23-belagswahl-bevorzugen"),
                               ("Nur bekannte befestigte Wege", "22-belagswahl-streng")] {
            app.buttons["routeProfile"].tap()
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout:5))
            app.buttons[title].tap()
            if title == "Nur bekannte befestigte Wege" {
                let tolerance = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "250 m je Lücke")).firstMatch
                for _ in 0..<3 where !tolerance.isHittable { app.swipeUp() }
                XCTAssertTrue(tolerance.isHittable)
                app.swipeUp() // Show the complete long footer, including offline limits.
                capture(app, "24-belagsluecken-profil")
            }
            app.buttons["Übernehmen"].tap()
            if app.alerts.firstMatch.waitForExistence(timeout:3) {
                app.alerts.buttons["Verstanden"].tap()
            }
            XCTAssertTrue(app.staticTexts["surfacePreferenceSummary"].waitForExistence(timeout:5))
            XCTAssertEqual(app.staticTexts["surfacePreferenceSummary"].label, title)
            capture(app, image)
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["surfacePreferenceSummary"].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["surfacePreferenceSummary"].label, "Nur bekannte befestigte Wege")
    }
    func testUnmappedPOIAccessKeepsVisibleRouteAndParking() {
        let app = launch()
        XCTAssertEqual(app.textFields["tourName"].value as? String, "Zielzugang · UI-Beispiel")
        XCTAssertTrue(app.buttons["Rad abstellen"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Wegdaten zum Ziel fehlen")).firstMatch.exists)
        capture(app,"20-zielzugang-karte")
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Fußrest nicht berechnet")).firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Rad abstellen"].exists)
        capture(app,"21-zielzugang-details")
    }
    func testMixedExampleShowsParkingAndSeparateDistancesOffline() {
        let app = launch()
        XCTAssertTrue(app.textFields["tourName"].value as? String == "Rad & Wandern · UI-Beispiel")
        XCTAssertTrue(app.buttons["Höhenprofil und Wegbeläge"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Rad abstellen"].waitForExistence(timeout:5))
        capture(app,"18-rad-wandern-karte")
        app.buttons["Höhenprofil und Wegbeläge"].tap()
        XCTAssertTrue(app.staticTexts["Rad abstellen"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Wandern: ")).firstMatch.exists)
        capture(app,"19-rad-wandern-details")
    }
}

final class MapStyleTests: XCTestCase {
    func testStylesSwitchAcrossTabsAndRestartWithGermanDefault() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://beispiel.invalid"
        app.launchEnvironment["BIKENAVI_TOKEN"] = ""
        app.launchEnvironment["BIKENAVI_PLAN_ID"] = "123C7446-B126-41E7-82E3-64D572AFA78B"
        app.launch()
        let menu = app.buttons["mapStyleMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        XCTAssertEqual(menu.value as? String, "Standard · Deutsch")
        let title = app.textFields["tourName"].value as? String
        XCTAssertTrue(["Heidelberg · Beispieltour", "Heidelberg · Höhenbeispiel"].contains(title ?? ""), "Galerie nur mit gekennzeichneten öffentlichen Beispieldaten erstellen")
        for (name, image) in [("Hell", "25-karte-hell"), ("Detailreich", "26-karte-detailreich"),
                              ("Dunkel", "27-karte-dunkel"), ("Satellit", "28-karte-satellit"),
                              ("Topografisch", "29-karte-topografisch")] {
            menu.tap()
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
            app.buttons[name].tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            XCTAssertEqual(menu.value as? String, name)
            XCTAssertEqual(app.textFields["tourName"].value as? String, title)
            capture(app, image)
        }
        app.tabBars.buttons["Einstellungen"].tap()
        let picker = app.buttons["settingsMapStyle"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Topografisch"))
        picker.tap()
        app.buttons["Standard · Deutsch"].tap()
        capture(app, "11-einstellungen")
        app.tabBars.buttons["Planen"].tap()
        XCTAssertEqual(menu.value as? String, "Standard · Deutsch")
        let toggle = app.buttons["togglePlanningDetails"]
        if !app.buttons["waypoints"].exists { toggle.tap() }
        capture(app, "01-planen")
        toggle.tap()
        capture(app, "02-karte")
        menu.tap()
        app.buttons["Dunkel"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(menu.value as? String, "Dunkel")
        app.terminate()
        app.launch()
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        XCTAssertEqual(menu.value as? String, "Standard · Deutsch")
        XCTAssertEqual(app.textFields["tourName"].value as? String, title)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let ready = expectation(description: "Kartenkacheln laden")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { ready.fulfill() }
        wait(for: [ready], timeout: 8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Gallery-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Run with the disposable HTTPS example server from the navigation QA workflow.
final class BlogProgressUITests: XCTestCase {
    @MainActor
    func testRealPiJobProgressSurvivesNavigationAndAppRestart() async throws {
        let health = URL(string: "https://127.0.0.1:18443/health")!
        var request = URLRequest(url: health)
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw XCTSkip("Start the disposable HTTPS blog-progress example server first.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["BIKENAVI_SERVER"] = "https://127.0.0.1:18443"
        app.launchEnvironment["BIKENAVI_TOKEN"] = "example-progress-token-" + String(repeating: "x", count: 40)
        func openRide() {
            app.tabBars.buttons["Touren"].tap()
            app.segmentedControls.buttons["Gefahren"].tap()
            let entry = app.cells.containing(.staticText, identifier: "Heidelberg · Beispielaufzeichnung").firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
            XCTAssertTrue(app.buttons["generateBlog"].waitForExistence(timeout: 5))
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Gallery-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.launch()
        openRide()
        app.buttons["generateBlog"].tap()
        XCTAssertTrue(app.staticTexts["Bilder und Karten vorbereiten …"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["generateBlog"].isEnabled)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        capture("42-blog-fortschritt")
        XCTAssertTrue(app.staticTexts["Ortsquellen recherchieren …"].waitForExistence(timeout: 15))
        let journal = app.buttons["openBlogJournal"]
        for _ in 0..<5 { if journal.isHittable { break }; app.swipeUp() }
        journal.tap()
        XCTAssertTrue(app.staticTexts["Ortsquellen recherchieren …"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["generateBlog"].isEnabled)
        app.terminate()
        app.launch()
        openRide()
        XCTAssertTrue(app.staticTexts["Deinen Blog schreiben …"].waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["generateBlog"].isEnabled)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50)))
        capture("43-blog-schreiben")
        XCTAssertTrue(app.staticTexts["Dein Blog ist fertig."].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["generateBlog"].isEnabled)
        XCTAssertTrue(app.buttons["previewBlog"].exists)
        app.terminate()
    }
}
