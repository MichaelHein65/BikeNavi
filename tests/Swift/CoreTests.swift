import XCTest
@testable import BikeNaviCore

final class CoreTests: XCTestCase {
    func testReroutingWaitsForSustainedSignificantDeviationAndUsesCooldown() {
        var policy = ReroutePolicy()
        XCTAssertFalse(policy.observe(distanceFromRoute: 79, timestamp: 100))
        XCTAssertFalse(policy.observe(distanceFromRoute: 90, timestamp: 101))
        XCTAssertFalse(policy.observe(distanceFromRoute: 90, timestamp: 110))
        XCTAssertTrue(policy.observe(distanceFromRoute: 90, timestamp: 111))
        XCTAssertFalse(policy.observe(distanceFromRoute: 120, timestamp: 122))
        XCTAssertFalse(policy.observe(distanceFromRoute: 120, timestamp: 200))
        XCTAssertTrue(policy.observe(distanceFromRoute: 120, timestamp: 201))
    }
    func store() throws -> LocalStore {
        try LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.sqlite"))
    }
    func route() -> CalculatedRoute {
        CalculatedRoute(id: UUID(), coordinates: [Coordinate(latitude: 49, longitude: 8), Coordinate(latitude: 49.01, longitude: 8), Coordinate(latitude: 49.01, longitude: 8.01)], distance: 1800, duration: 400, ascent: 10, descent: 4,
                        maneuvers: [Maneuver(instruction: "Rechts", distance: 1000, coordinateIndex: 1, type: 1)],
                        surfaces: [], warnings: [], provider: "test", calculatedAt: 1)
    }
    func testOfflineSaveSurvivesReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("db.sqlite")
        let id: UUID
        do {
            let db = try LocalStore(url: url)
            var document = TourDocument()
            document.title = "Wald & Wasser"
            document.route = route()
            id = document.id
            try db.save(document)
        }
        let reopened = try LocalStore(url: url)
        let record = try XCTUnwrap(reopened.all().first)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.document.title, "Wald & Wasser")
        XCTAssertTrue(record.dirty)
        XCTAssertEqual(record.document.route?.coordinates.count, 3)
    }
    func testSavedPlaceSurvivesReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("places.sqlite")
        let place = SavedPlace(name: "Lieblingscafé", coordinate: Coordinate(latitude: 49.4, longitude: 8.7))
        try LocalStore(url: url).save(place)
        let restored = try LocalStore(url: url).places()
        XCTAssertEqual(restored, [place])
        XCTAssertNotEqual(restored[0].waypoint.id, restored[0].id)
    }
    func testSavedPlaceCanBeRenamedWithoutChangingItsIdentity() throws {
        let db = try store()
        var place = SavedPlace(name: "Unbenannt", coordinate: Coordinate(latitude: 49.4, longitude: 8.7))
        let identifier = place.id
        try db.save(place)
        place.name = "Zuhause"
        try db.save(place)
        let restored = try XCTUnwrap(db.places().first)
        XCTAssertEqual(restored.id, identifier)
        XCTAssertEqual(restored.name, "Zuhause")
    }
    func testReversingAPlanReversesAllWaypoints() {
        var document = TourDocument()
        let start = Waypoint(name: "Start", coordinate: Coordinate(latitude: 49, longitude: 8))
        let via = Waypoint(name: "Pause", coordinate: Coordinate(latitude: 49.1, longitude: 8.1))
        let destination = Waypoint(name: "Ziel", coordinate: Coordinate(latitude: 49.2, longitude: 8.2))
        document.waypoints = [start, via, destination]
        XCTAssertTrue(document.reverseWaypoints())
        XCTAssertEqual(document.waypoints, [destination, via, start])
        var incomplete = TourDocument()
        incomplete.waypoints = [destination]
        XCTAssertFalse(incomplete.reverseWaypoints())
    }
    func testAutomaticTitlePrefersNearbySavedPlacesAndStaysShort() {
        var document = TourDocument()
        document.waypoints = [
            Waypoint(name: "Eine sehr lange Straßenadresse 12, Rodgau, Hessen, Deutschland", coordinate: Coordinate(latitude: 49.9995, longitude: 8)),
            Waypoint(name: "Ausflugsziel am See, Seligenstadt, Hessen, Deutschland", coordinate: Coordinate(latitude: 50.1, longitude: 8.1)),
        ]
        let home = SavedPlace(name: "Zuhause", coordinate: Coordinate(latitude: 50, longitude: 8))
        let tooFarAway = SavedPlace(name: "Nicht dieses Ziel", coordinate: Coordinate(latitude: 50.102, longitude: 8.1))
        document.updateAutomaticTitle(savedPlaces: [home, tooFarAway])
        XCTAssertEqual(document.title, "Zuhause → Ausflugsziel am See")
        XCTAssertLessThanOrEqual(document.title.count, 67)
    }
    func testAcknowledgmentDoesNotEraseAnEditMadeDuringUpload() throws {
        let db = try store()
        var document = TourDocument()
        try db.save(document)
        let uploaded = try XCTUnwrap(db.all().first)
        document.title = "Änderung während Upload"
        try db.save(document)
        try db.acknowledge(uploaded, remote: RemoteRecord(document: uploaded.document, revision: 1, deleted: false))
        let pending = try XCTUnwrap(db.all().first)
        XCTAssertTrue(pending.dirty)
        XCTAssertEqual(pending.revision, 1)
        XCTAssertEqual(pending.document.title, document.title)
    }
    func testConflictPreservesBothGeometriesAndIDs() throws {
        let db = try store()
        var document = TourDocument()
        document.route = route()
        try db.save(document)
        let record = try XCTUnwrap(db.all().first)
        try db.preserveConflict(record)
        var remote = document
        remote.title = "Vom anderen Gerät"
        try db.merge(RemoteRecord(document: remote, revision: 2, deleted: false))
        let records = try db.all()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.id)).count, 2)
        XCTAssertTrue(records.contains { $0.document.title.hasSuffix("lokale Fassung") && $0.dirty })
        XCTAssertTrue(records.contains { $0.document.title == remote.title && !$0.dirty })
        XCTAssertTrue(records.allSatisfy { $0.document.route == document.route })
    }
    func testOldServerVersionCannotOverwriteNewerLocalVersion() throws {
        let db = try store()
        let document = TourDocument()
        try db.merge(RemoteRecord(document: document, revision: 5, deleted: false))
        var old = document
        old.title = "Alte Fassung"
        try db.merge(RemoteRecord(document: old, revision: 3, deleted: true))
        let current = try XCTUnwrap(db.all().first)
        XCTAssertFalse(current.deleted)
        XCTAssertEqual(current.revision, 5)
    }
    func testNavigationUsesDistanceAlongRouteAndDetectsDeviation() {
        var tracker = RouteTracker()
        let planned = route()
        let onRoute = tracker.update(position: Coordinate(latitude: 49.005, longitude: 8), timestamp: 100, route: planned)!
        XCTAssertLessThan(onRoute.distanceFromRoute, 2)
        XCTAssertEqual(onRoute.nextManeuver?.instruction, "Rechts")
        XCTAssertGreaterThan(onRoute.distanceToManeuver, 500)
        let offRoute = tracker.update(position: Coordinate(latitude: 49.005, longitude: 8.005), timestamp: 110, route: planned)!
        XCTAssertGreaterThan(offRoute.distanceFromRoute, 100)
        XCTAssertEqual(offRoute.traveled, onRoute.traveled)
    }
    func testRecordingRejectsStaleInaccurateAndImpossibleGPSPoints() {
        let first = TrackPoint(coordinate: Coordinate(latitude: 49, longitude: 8), timestamp: 100, accuracy: 5, speed: 4, segment: 0)
        XCTAssertTrue(TrackFilter.accepts(first, after: nil, now: 100))
        XCTAssertFalse(TrackFilter.accepts(first, after: nil, now: 200))
        var bad = first
        bad.accuracy = 200
        XCTAssertFalse(TrackFilter.accepts(bad, after: nil, now: 100))
        bad = first; bad.timestamp = 104; bad.coordinate.latitude = 50
        XCTAssertFalse(TrackFilter.accepts(bad, after: first, now: 104))
    }
    func testPausedTrackDoesNotConnectSeparateSegmentsAndGPXEscapesNames() {
        var ride = TourDocument()
        ride.kind = .ride
        ride.title = "Wald < See & Tour"
        ride.track = [TrackPoint(coordinate: Coordinate(latitude: 49, longitude: 8), timestamp: 1, accuracy: 5, speed: 0, segment: 0),
                      TrackPoint(coordinate: Coordinate(latitude: 50, longitude: 8), timestamp: 300, accuracy: 5, speed: 0, segment: 1)]
        XCTAssertEqual(ride.recordedDistance, 0)
        let xml = GPX.xml(ride)
        XCTAssertTrue(xml.contains("Wald &lt; See &amp; Tour"))
        XCTAssertEqual(xml.components(separatedBy: "<trkseg>").count - 1, 2)
    }
    func testPlanningAnOldRideDoesNotModifyItsTrack() {
        var ride = TourDocument()
        ride.kind = .ride
        ride.startedAt = 1
        ride.recordingState = .finished
        let copy = ride.asNewPlan()
        XCTAssertNotEqual(copy.id, ride.id)
        XCTAssertEqual(copy.kind, .plan)
        XCTAssertNil(copy.startedAt)
        XCTAssertEqual(ride.startedAt, 1)
    }
    func testRealORSResponseDecodesForTheApp() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/heidelberg-route.json")
        let route = try JSONDecoder().decode(CalculatedRoute.self, from: Data(contentsOf: file))
        XCTAssertGreaterThan(route.distance, 500)
        XCTAssertEqual(route.coordinates.first?.latitude ?? 0, 49.4146, accuracy: 0.001)
        XCTAssertFalse(route.maneuvers.isEmpty)
        XCTAssertTrue(route.coordinates.allSatisfy { $0.altitude != nil })
    }

    func testAutomaticTourNameFollowsEndpointsAfterSavingAndReopening() throws {
        let db = try store()
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Rodgau", coordinate: Coordinate(latitude: 50, longitude: 8.8)),
                              Waypoint(name: "Seligenstadt", coordinate: Coordinate(latitude: 50.04, longitude: 8.97))]
        document.updateAutomaticTitle()
        XCTAssertEqual(document.title, "Rodgau → Seligenstadt")
        try db.save(document)
        var reopened = try XCTUnwrap(db.all().first).document
        reopened.waypoints.reverse()
        reopened.updateAutomaticTitle()
        XCTAssertEqual(reopened.title, "Seligenstadt → Rodgau")
        reopened.waypoints.removeLast()
        reopened.updateAutomaticTitle()
        XCTAssertEqual(reopened.title, "Meine nächste Tour")
    }

    func testLatePlaceNameCannotOverwriteCustomTourNameOrMovePoint() throws {
        let point = Waypoint(name: "Kartenpunkt", coordinate: Coordinate(latitude: 50, longitude: 8.8))
        var document = TourDocument()
        document.waypoints = [point, Waypoint(name: "Seligenstadt", coordinate: Coordinate(latitude: 50.04, longitude: 8.97))]
        document.updateAutomaticTitle()
        document.rename(to: "Unsere Sonntagsrunde")
        document = try JSONDecoder().decode(TourDocument.self, from: JSONEncoder().encode(document))
        XCTAssertTrue(document.resolveName("Rodgau", for: point))
        XCTAssertEqual(document.waypoints[0].coordinate, point.coordinate)
        XCTAssertEqual(document.title, "Unsere Sonntagsrunde")
        document.rename(to: "  ")
        document.finishRenaming()
        XCTAssertEqual(document.title, "Rodgau → Seligenstadt")
    }

    func testReplacedWaypointRejectsDelayedPlaceName() {
        let oldPoint = Waypoint(name: "Kartenpunkt", coordinate: Coordinate(latitude: 50, longitude: 8.8))
        var document = TourDocument()
        var moved = oldPoint
        moved.coordinate.longitude = 9
        document.waypoints = [moved, Waypoint(name: "Ziel", coordinate: Coordinate(latitude: 50.1, longitude: 9))]
        XCTAssertFalse(document.resolveName("Alter Ort", for: oldPoint))
        XCTAssertEqual(document.waypoints.first?.name, "Kartenpunkt")
    }

    func testOldDocumentsGainAutomaticNamesWithoutRenamingCustomTitles() throws {
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Rodgau", coordinate: Coordinate(latitude: 50, longitude: 8.8)),
                              Waypoint(name: "Seligenstadt", coordinate: Coordinate(latitude: 50.04, longitude: 8.97))]
        let data = try JSONEncoder().encode(document)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("usesAutomaticTitle"))
        var legacy = try JSONDecoder().decode(TourDocument.self, from: data)
        legacy.updateAutomaticTitle()
        XCTAssertEqual(legacy.title, "Rodgau → Seligenstadt")
        document.title = "Schon benannte Tour"
        legacy = try JSONDecoder().decode(TourDocument.self, from: JSONEncoder().encode(document))
        legacy.updateAutomaticTitle()
        XCTAssertEqual(legacy.title, "Schon benannte Tour")
    }

    func testLongPlaceNamesFitServerTitleLimitAndCopyKeepsItsName() {
        var document = TourDocument()
        document.waypoints = [Waypoint(name: String(repeating: "A", count: 300), coordinate: Coordinate(latitude: 50, longitude: 8.8)),
                              Waypoint(name: String(repeating: "B", count: 300), coordinate: Coordinate(latitude: 50.04, longitude: 8.97))]
        document.updateAutomaticTitle()
        XCTAssertLessThanOrEqual(document.title.count, 200)
        var copy = document.asNewPlan()
        copy.updateAutomaticTitle()
        XCTAssertTrue(copy.title.hasSuffix(" · Kopie"))
    }

    func testSurfaceBoundariesShareOneCoordinateAndSurviveOfflineStorage() throws {
        var planned = route()
        planned.surfaceSections = [RouteSurfaceSection(startIndex: 0, endIndex: 1, surface: 3),
                                   RouteSurfaceSection(startIndex: 1, endIndex: 2, surface: 10)]
        var document = TourDocument()
        document.route = planned
        let db = try store()
        try db.save(document)
        let restored = try XCTUnwrap(db.all().first?.document.route)
        XCTAssertEqual(restored.coloredSections.map(\.kind), [.paved, .gravel])
        let lines = restored.coloredSections.map { Array(restored.coordinates[$0.startIndex...$0.endIndex]) }
        XCTAssertEqual(lines[0].last, lines[1].first)
        XCTAssertEqual(lines.map(\.count), [2, 2])
    }

    func testMissingSurfaceEdgesRemainUnknownInsteadOfUsingTotals() {
        var planned = route()
        planned.surfaces = [SurfaceSummary(name: "Asphalt", distance: 1800, percentage: 100)]
        XCTAssertEqual(planned.coloredSections.map(\.kind), [.unknown])
        planned.surfaceSections = [RouteSurfaceSection(startIndex: 1, endIndex: 2, surface: 3)]
        XCTAssertEqual(planned.coloredSections.map(\.kind), [.unknown, .paved])
        XCTAssertEqual(planned.coloredSections.first?.endIndex, 1)
        planned.surfaceSections = [RouteSurfaceSection(startIndex: 0, endIndex: 1, surface: 10)]
        XCTAssertEqual(planned.coloredSections.map(\.kind), [.gravel, .unknown])
    }

    func testInvalidLocalSurfaceGeometryFallsBackWithoutIndexCrash() {
        var planned = route()
        for invalid in [RouteSurfaceSection(startIndex: -1, endIndex: 1, surface: 3),
                        RouteSurfaceSection(startIndex: 0, endIndex: 99, surface: 3)] {
            planned.surfaceSections = [invalid]
            XCTAssertEqual(planned.coloredSections.map(\.kind), [.unknown])
        }
    }

    func testDestinationFirstUsesCurrentLocationWithoutReplacingExplicitStart() {
        let here = Coordinate(latitude: 49, longitude: 8)
        let destination = Waypoint(name: "Ziel", coordinate: Coordinate(latitude: 50, longitude: 9))
        var plan = TourDocument()
        plan.setDestination(destination, currentPosition: here)
        XCTAssertEqual(plan.startPoint?.coordinate, here)
        XCTAssertEqual(plan.destinationPoint, destination)
        XCTAssertTrue(plan.canCalculateRoute)
        XCTAssertFalse(plan.isAwaitingStart)
        let manualStart = Waypoint(name: "Bahnhof", coordinate: Coordinate(latitude: 48, longitude: 8))
        plan.setStart(manualStart)
        plan.setDestination(destination, currentPosition: here)
        XCTAssertEqual(plan.startPoint, manualStart)
    }

    func testDestinationWaitsForGPSAcrossRestartAndUsesOnlyLatestDestination() throws {
        let db = try store()
        let first = Waypoint(name: "Erstes Ziel", coordinate: Coordinate(latitude: 50, longitude: 9))
        let latest = Waypoint(name: "Neues Ziel", coordinate: Coordinate(latitude: 51, longitude: 9))
        var plan = TourDocument()
        plan.setDestination(first, currentPosition: nil)
        XCTAssertNil(plan.startPoint)
        XCTAssertEqual(plan.destinationPoint, first)
        XCTAssertFalse(plan.canCalculateRoute)
        try db.save(plan)
        var restored = try XCTUnwrap(db.all().first).document
        restored.setDestination(latest, currentPosition: nil)
        XCTAssertEqual(restored.waypoints.count, 1)
        XCTAssertTrue(restored.completeAutomaticStart(Coordinate(latitude: 49, longitude: 8)))
        XCTAssertEqual(restored.destinationPoint, latest)
        XCTAssertEqual(restored.waypoints.count, 2)
        XCTAssertFalse(restored.completeAutomaticStart(Coordinate(latitude: 45, longitude: 5)))
    }

    func testManualStartWinsOverDelayedGPSAndPendingViasAreNotRoutedAsStart() {
        var plan = TourDocument()
        let destination = Waypoint(name: "Ziel", coordinate: Coordinate(latitude: 50, longitude: 9))
        let via = Waypoint(name: "Café", coordinate: Coordinate(latitude: 49.5, longitude: 8.5))
        plan.setDestination(destination, currentPosition: nil)
        plan.waypoints.insert(via, at: 0)
        XCTAssertFalse(plan.canCalculateRoute)
        let start = Waypoint(name: "Bahnhof", coordinate: Coordinate(latitude: 49, longitude: 8))
        plan.setStart(start)
        XCTAssertFalse(plan.completeAutomaticStart(Coordinate(latitude: 48, longitude: 7)))
        XCTAssertEqual(plan.waypoints, [start, via, destination])
        XCTAssertTrue(plan.canCalculateRoute)
    }

    func testAutomaticStartRejectsOldOrInaccurateLocations() {
        XCTAssertTrue(PlanningLocation.isUsable(timestamp: 100, accuracy: 10, now: 105))
        XCTAssertFalse(PlanningLocation.isUsable(timestamp: 100, accuracy: 10, now: 130))
        XCTAssertFalse(PlanningLocation.isUsable(timestamp: 100, accuracy: 1000, now: 105))
        XCTAssertFalse(PlanningLocation.isUsable(timestamp: 100, accuracy: -1, now: 105))
    }
}
