import XCTest
@testable import BikeNaviCore

final class RouteDescriptionTests: XCTestCase {
    private func plan() -> TourDocument {
        var p = TourDocument()
        p.waypoints = [.init(name: "Beispielstart", coordinate: .init(latitude: 49, longitude: 8)),
                       .init(name: "Beispielziel", coordinate: .init(latitude: 49.001, longitude: 8))]
        p.route = CalculatedRoute(id: UUID(), coordinates: p.waypoints.map(\.coordinate), distance: 100, duration: 30,
                                 ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [], provider: "synthetic", calculatedAt: 1)
        return p
    }

    func testDescriptionRequiresCalculatedPlanAndIsIndependentOfRide() {
        var p = plan()
        XCTAssertNotNil(RouteDescriptionRequest(plan: p))
        p.kind = .ride
        XCTAssertNil(RouteDescriptionRequest(plan: p))
        p.kind = .plan; p.route = nil
        XCTAssertNil(RouteDescriptionRequest(plan: p))
    }

    func testFingerprintCoversRouteWaypointsProfileAndTitleButNotSyncTimestamps() throws {
        let p = plan()
        let original = try XCTUnwrap(RouteDescriptionRequest(plan: p)).fingerprint
        var changed = p
        changed.updatedAt += 100
        XCTAssertEqual(try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint, original)
        changed.title = "Andere Tour"
        XCTAssertNotEqual(try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint, original)
        changed = p; changed.waypoints[1].name = "Anderes Ziel"
        XCTAssertNotEqual(try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint, original)
        changed = p; changed.profile.electric.toggle()
        XCTAssertNotEqual(try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint, original)
        changed = p; changed.route!.coordinates[1].latitude += 0.01
        XCTAssertNotEqual(try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint, original)
    }

    func testLocalDescriptionSurvivesRestartAndDetectsStalePlanning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        var p = plan()
        let fingerprint = try XCTUnwrap(RouteDescriptionRequest(plan: p)).fingerprint
        let report = RouteDescriptionReport(planID: p.id, routeID: p.route!.id, createdAt: 1, html: "<h1>Beispiel</h1>", mode: "template", sourceCount: 0, imageCount: 0, warnings: [])
        let saved = SavedRouteDescription(planID: p.id, fingerprint: fingerprint,
            job: .init(generationID: UUID(), planID: p.id, phase: "completed"), report: report, reportFingerprint: fingerprint)
        do { let store = try LocalStore(url: url); try store.saveRouteDescription(saved) }
        let store = try LocalStore(url: url)
        let reopened = try XCTUnwrap(store.routeDescription(planID: p.id))
        XCTAssertEqual(reopened.report?.html, report.html)
        XCTAssertTrue(reopened.matches(p))
        p.waypoints[1].coordinate.latitude += 1
        XCTAssertFalse(reopened.matches(p))
        XCTAssertNil(try store.blogDraft(rideID: p.id))
        XCTAssertNil(try store.routeDescription(planID: UUID()))
    }

    func testPendingDescriptionKeepsPreviousReportAndFingerprintSeparate() throws {
        let p = plan()
        let report = RouteDescriptionReport(planID: p.id, routeID: p.route!.id, createdAt: 1, html: "Alt", mode: "template", sourceCount: 0, imageCount: 0, warnings: [])
        let saved = SavedRouteDescription(planID: p.id, fingerprint: "neue Anfrage",
            job: .init(generationID: UUID(), planID: p.id, phase: "researching"), report: report, reportFingerprint: "alte Route")
        let decoded = try JSONDecoder().decode(SavedRouteDescription.self, from: JSONEncoder().encode(saved))
        XCTAssertTrue(decoded.job.running)
        XCTAssertFalse(decoded.matches(p))
        XCTAssertEqual(decoded.report?.html, "Alt")
    }

    func testChangedRouteStartsFreshDescriptionButSameFailedRequestNeedsExplicitRetry() throws {
        let p = plan()
        let fingerprint = try XCTUnwrap(RouteDescriptionRequest(plan: p)).fingerprint
        let report = RouteDescriptionReport(planID: p.id, routeID: p.route!.id, createdAt: 1, html: "Alte Route", mode: "template", sourceCount: 0, imageCount: 0, warnings: [])
        var saved = SavedRouteDescription(planID: p.id, fingerprint: fingerprint,
            job: .init(generationID: UUID(), planID: p.id, phase: "completed"), report: report, reportFingerprint: fingerprint)
        XCTAssertFalse(saved.needsCreationOnOpen(p))
        var changed = p
        changed.route!.id = UUID()
        changed.waypoints[1].coordinate.latitude += 0.01
        XCTAssertTrue(saved.needsCreationOnOpen(changed))
        saved.fingerprint = try XCTUnwrap(RouteDescriptionRequest(plan: changed)).fingerprint
        saved.job.phase = "failed"
        XCTAssertFalse(saved.matches(changed))
        XCTAssertTrue(saved.requestMatches(changed))
        XCTAssertFalse(saved.needsCreationOnOpen(changed))
        saved.job.phase = "researching"
        XCTAssertFalse(saved.needsCreationOnOpen(changed))
        changed.id = UUID()
        XCTAssertTrue(saved.needsCreationOnOpen(changed))
    }
    private func threeStopPlan() -> TourDocument {
        var p = plan()
        p.waypoints = [0, 2, 5].map { Waypoint(name: "Ziel \($0)", coordinate: .init(latitude: 49 + Double($0) * 0.001, longitude: 8)) }
        p.route!.coordinates = (0...5).map { .init(latitude: 49 + Double($0) * 0.001, longitude: 8) }
        p.route!.waypointIndices = [0, 2, 5]
        return p
    }
    private func highlight(_ plan: TourDocument, latitude: Double, start: Int, end: Int) -> RouteDescriptionHighlight {
        .init(id: UUID(), title: "Beispielhighlight", coordinate: .init(latitude: latitude, longitude: 8.001), routeDistance: 100,
              startWaypointID: plan.waypoints[start].id, endWaypointID: plan.waypoints[end].id)
    }
    func testHighlightInsertedWithinItsOriginalLegWithoutReplacingOtherGoals() throws {
        let p = threeStopPlan()
        for (latitude, start, end, position) in [(49.001, 0, 1, 1), (49.004, 1, 2, 2)] {
            let h = highlight(p, latitude: latitude, start: start, end: end)
            let updated = try RouteDescriptionInsertion.inserting(h, into: p)
            XCTAssertEqual(updated.waypoints[position].id, h.id)
            XCTAssertEqual(updated.waypoints.filter { $0.id != h.id }, p.waypoints)
            XCTAssertEqual(updated.profile, p.profile)
            XCTAssertNil(updated.route)
            XCTAssertNotNil(p.route)
        }
    }
    func testMultipleHighlightsInSameLegAreInsertedAlongCurrentRoute() throws {
        let p = threeStopPlan()
        let later = highlight(p, latitude: 49.0018, start: 0, end: 1)
        var updated = try RouteDescriptionInsertion.inserting(later, into: p)
        updated.route = p.route
        updated.route!.waypointIndices = nil
        let earlier = highlight(p, latitude: 49.0005, start: 0, end: 1)
        let final = try RouteDescriptionInsertion.inserting(earlier, into: updated)
        XCTAssertEqual(final.waypoints.map(\.id), [p.waypoints[0].id, earlier.id, later.id, p.waypoints[1].id, p.waypoints[2].id])
    }
    func testHighlightOutsideLegChangedAnchorsAndDuplicatesAreRejected() throws {
        let p = threeStopPlan()
        var h = highlight(p, latitude: 49.001, start: 0, end: 1)
        h.coordinate.longitude = 9
        XCTAssertThrowsError(try RouteDescriptionInsertion.inserting(h, into: p))
        h = highlight(p, latitude: 49.001, start: 0, end: 1)
        h.startWaypointID = UUID()
        XCTAssertThrowsError(try RouteDescriptionInsertion.inserting(h, into: p))
        h = highlight(p, latitude: 49.001, start: 1, end: 0)
        XCTAssertThrowsError(try RouteDescriptionInsertion.inserting(h, into: p))
        h = highlight(p, latitude: 49.001, start: 0, end: 1)
        h.coordinate = p.waypoints[1].coordinate
        XCTAssertThrowsError(try RouteDescriptionInsertion.inserting(h, into: p))
    }
    func testOldDescriptionsRemainReadableAndExportRemovesOnlyAppActions() throws {
        let old = #"{"planID":"123C7446-B126-41E7-82E3-64D572AFA78B","routeID":"123C7446-B126-41E7-82E3-64D572AFA78B","createdAt":1,"html":"Beispiel","mode":"template","sourceCount":0,"imageCount":0,"warnings":[]}"#
        var report = try JSONDecoder().decode(RouteDescriptionReport.self, from: Data(old.utf8))
        XCTAssertNil(report.highlights)
        report.html = "<a class='add-highlight' href='bikenavi-highlight://insert/123C7446-B126-41E7-82E3-64D572AFA78B'>Als Zwischenziel einfügen</a><a href='https://example.org'>Quelle</a>"
        XCTAssertEqual(report.exportHTML, "<a href='https://example.org'>Quelle</a>")
    }

    func testMovedAnchorAndCoarseGeometryDoNotMisplaceQueuedHighlights() throws {
        let p = threeStopPlan()
        var h = highlight(p, latitude: 49.001, start: 0, end: 1)
        h.endWaypointCoordinate = p.waypoints[1].coordinate
        var changed = p
        changed.waypoints[1].coordinate.latitude += 0.01
        XCTAssertThrowsError(try RouteDescriptionInsertion.inserting(h, into: changed))
        var line = plan()
        line.waypoints[1].coordinate.latitude = 49.01
        line.route!.coordinates = line.waypoints.map(\.coordinate)
        line.route!.waypointIndices = [0, 1]
        let later = highlight(line, latitude: 49.004, start: 0, end: 1)
        var withLater = try RouteDescriptionInsertion.inserting(later, into: line)
        withLater.route = line.route
        let earlier = highlight(line, latitude: 49.002, start: 0, end: 1)
        let result = try RouteDescriptionInsertion.inserting(earlier, into: withLater)
        XCTAssertEqual(result.waypoints.map(\.id), [line.waypoints[0].id, earlier.id, later.id, line.waypoints[1].id])
    }

    func testOriginalIndicesProtectTheLaterVisitToAWaypointOnALoop() throws {
        var p = threeStopPlan()
        let start = p.waypoints[0]
        var via = p.waypoints[1]
        via.coordinate.latitude = 49.001
        var goal = p.waypoints[2]
        goal.coordinate.latitude = 49.03
        let existing = Waypoint(name: "Bereits ausgewählt", coordinate: .init(latitude: 49.0005, longitude: 8))
        p.waypoints = [start, existing, via, goal]
        p.route!.coordinates = [start.coordinate, via.coordinate, .init(latitude: 49.02, longitude: 8), via.coordinate, goal.coordinate]
        p.route!.waypointIndices = [0, 3, 4] // The original via is the later visit.
        let h = highlight(p, latitude: 49.019, start: 0, end: 2)
        let indices = [start.id.uuidString: 0, via.id.uuidString: 3, goal.id.uuidString: 4]
        let updated = try RouteDescriptionInsertion.inserting(h, into: p, referenceIndices: indices)
        XCTAssertEqual(updated.waypoints.map(\.id), [start.id, existing.id, h.id, via.id, goal.id])
    }

}
