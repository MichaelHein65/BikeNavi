import XCTest

final class PlannerUITests: XCTestCase {
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
