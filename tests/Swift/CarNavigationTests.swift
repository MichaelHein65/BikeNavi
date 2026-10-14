import XCTest
@testable import BikeNaviCore

final class CarNavigationTests: XCTestCase {
    private func route() -> CalculatedRoute {
        let points = (0...4).map { Coordinate(latitude: 49 + Double($0) * 0.001, longitude: 8) }
        return CalculatedRoute(id: UUID(), coordinates: points, distance: 445, duration: 90, ascent: 100, descent: 0,
            maneuvers: [.init(instruction: "Rechts auf die B 3 abbiegen", distance: 100, coordinateIndex: 2, type: 1),
                        .init(instruction: "Ziel erreicht", distance: 0, coordinateIndex: 4, type: 10)],
            surfaces: [], warnings: [], provider: "synthetic car example", calculatedAt: 0,
            waypointIndices: [0, 2, 3, 4], carTimeSections: [.init(startIndex: 0, endIndex: 2, seconds: 60), .init(startIndex: 2, endIndex: 4, seconds: 30)])
    }
    private func progress(distance: Double) -> RouteProgress {
        RouteProgress(traveled: 0, remaining: 1000, distanceFromRoute: 0,
            nextManeuver: .init(instruction: "Rechts abbiegen", distance: 0, coordinateIndex: 2, type: 1), distanceToManeuver: distance)
    }
    func testSpeedViewAndActionViewIncludeCloseFollowingManeuver() {
        var slow = CarAutoZoom(), fast = CarAutoZoom(), action = CarAutoZoom(), chain = CarAutoZoom()
        let city = slow.update(speed: 5, timestamp: 1, progress: nil)
        let highway = fast.update(speed: 36, timestamp: 1, progress: nil)
        let turn = action.update(speed: 36, timestamp: 1, progress: progress(distance: 400))
        let pair = chain.update(speed: 36, timestamp: 1, progress: progress(distance: 400), followingGap: 200)
        XCTAssertGreaterThan(highway, city * 3)
        XCTAssertLessThan(turn, highway)
        XCTAssertGreaterThan(pair, turn)
        XCTAssertGreaterThan(pair, 600)
    }
    func testZoomSmoothsStopAndGoRejectsDuplicateTimeAndHoldsWithoutFreshNavigation() {
        var zoom = CarAutoZoom()
        let highway = zoom.update(speed: 36, timestamp: 1, progress: nil)
        let braking = zoom.update(speed: 0, timestamp: 2, progress: nil)
        XCTAssertLessThan(braking, highway)
        XCTAssertGreaterThan(braking, highway * 0.85)
        XCTAssertEqual(zoom.update(speed: 0, timestamp: 2, progress: nil), braking)
        XCTAssertEqual(zoom.update(speed: 0, timestamp: 3, progress: nil, active: false), braking)
        XCTAssertEqual(zoom.update(speed: 0, timestamp: 4, progress: nil, fresh: false), braking)
        XCTAssertEqual(zoom.update(speed: 0, timestamp: 5, progress: nil, rerouting: true), braking)
        let returning = zoom.update(speed: 36, timestamp: 6, progress: nil)
        XCTAssertLessThan(abs(returning - braking), 200)
    }
    func testComplexExitGetsEarlierCameraFocusThanOrdinaryTurn() {
        var turn = CarAutoZoom(), exit = CarAutoZoom()
        let ordinary = progress(distance: 1300)
        var complex = ordinary; complex.nextManeuver?.type = 12
        let normal = turn.update(speed: 36, timestamp: 1, progress: ordinary)
        let focused = exit.update(speed: 36, timestamp: 1, progress: complex)
        XCTAssertLessThan(focused, normal)
        XCTAssertGreaterThan(focused, complex.distanceToManeuver)
    }
    func testVoiceHasEarlyReminderAndImmediateStagesWithoutDuplicates() {
        var voice = CarVoiceGuidance()
        XCTAssertNotNil(voice.announcement(progress: progress(distance: 1000), speed: 36, following: nil))
        XCTAssertNil(voice.announcement(progress: progress(distance: 900), speed: 36, following: nil))
        XCTAssertNotNil(voice.announcement(progress: progress(distance: 400), speed: 36, following: nil))
        XCTAssertTrue(voice.announcement(progress: progress(distance: 50), speed: 36, following: nil)?.hasPrefix("Jetzt") == true)
        XCTAssertNil(voice.announcement(progress: progress(distance: 40), speed: 36, following: nil))
        var off = progress(distance: 10); off.distanceFromRoute = 50
        XCTAssertNil(voice.announcement(progress: off, speed: 36, following: nil))
    }
    func testRoundaboutAndRoadNamesRemainInCarGuidance() {
        let turn = Maneuver(instruction: "In den Kreisverkehr fahren", distance: 100, coordinateIndex: 1, type: 7,
            roadName: "B 3", exitNumber: 3)
        XCTAssertTrue(turn.carInstruction.contains("3. Ausfahrt"))
        XCTAssertTrue(turn.carInstruction.contains("B 3"))
        let complete = Maneuver(instruction: "Dritte Ausfahrt auf die B 3 nehmen", distance: 100, coordinateIndex: 1,
            type: 7, roadName: "B 3", exitNumber: 3)
        XCTAssertEqual(complete.carInstruction, complete.instruction)
    }
    func testCarTimeUsesProviderSectionsRatherThanCyclingSurfacesAndClimb() {
        let route = route()
        var car = RidingProfile(); car.mode = .car
        let time = RouteTravelTime(route: route, profile: car)
        XCTAssertEqual(time.total, 90, accuracy: 0.001)
        XCTAssertEqual(time.remaining(after: LocalRouteMetrics.distances(route)[2]), 30, accuracy: 0.001)
        var legacy = route; legacy.carTimeSections = nil
        XCTAssertEqual(RouteTravelTime(route: legacy, profile: car).total, 90, accuracy: 0.001)
    }
    func testUnvisitedStopsStayMandatoryAcrossReplacementAndArrival() {
        let route = route()
        var ride = TourDocument(); ride.kind = .ride; ride.profile.mode = .car; ride.route = route
        ride.waypoints = [0, 2, 3, 4].map { Waypoint(name: "Beispiel", coordinate: route.coordinates[$0]) }
        ride.localNavigation = LocalNavigationState(carPendingWaypointOrdinals: [1, 2, 3])
        var p = RouteProgress(traveled: 1000, remaining: 0, distanceFromRoute: 60, nextManeuver: nil, distanceToManeuver: 0)
        XCTAssertEqual(CarNavigation.remaining(ride: ride, route: route, progress: p, position: route.coordinates[4]), [1, 2, 3])
        p.snappedPosition = route.coordinates[4]; p.distanceFromRoute = 0
        let held = CarNavigation.requiringUnvisitedStop(ride: ride, route: route, progress: p, position: route.coordinates[4])
        XCTAssertNil(held.snappedPosition)
        XCTAssertGreaterThan(held.distanceFromRoute, 35)
        ride.localNavigation?.carRoute = route
        p.snappedPosition = route.coordinates[2]; p.distanceFromRoute = 0; p.traveled = LocalRouteMetrics.distances(route)[2]
        let first = CarNavigation.remaining(ride: ride, route: route, progress: p, position: route.coordinates[2])
        XCTAssertEqual(first, [2, 3]); ride.localNavigation?.carPendingWaypointOrdinals = first
        p.traveled = LocalRouteMetrics.distances(route)[3]; p.snappedPosition = route.coordinates[3]
        XCTAssertEqual(CarNavigation.remaining(ride: ride, route: route, progress: p, position: route.coordinates[3]), [3])
        XCTAssertFalse(CarNavigation.arrived(route: route, progress: p, pending: [2, 3], position: route.coordinates[4]))
        XCTAssertTrue(CarNavigation.arrived(route: route, progress: p, pending: [3], position: route.coordinates[4]))
    }
    func testHighwayTrackAndProgressPermitRealSpeedButRejectImpossibleJumpsAndWrongDirection() {
        let route = route()
        let a = TrackPoint(coordinate: route.coordinates[0], timestamp: 0, accuracy: 5, speed: 40, segment: 0)
        let b = TrackPoint(coordinate: route.coordinates[2], timestamp: 5, accuracy: 5, speed: 40, segment: 0)
        XCTAssertFalse(TrackFilter.accepts(b, after: a, now: 5))
        XCTAssertTrue(TrackFilter.accepts(b, after: a, now: 5, mode: .car))
        var jump = b; jump.coordinate.latitude += 1
        XCTAssertFalse(TrackFilter.accepts(jump, after: a, now: 5, mode: .car))
        var tracker = RouteTracker(lastProgress: 0, lastTimestamp: 0)
        XCTAssertNotNil(tracker.update(position: route.coordinates[4], timestamp: 8, route: route, heading: 0, carNavigation: true)?.snappedPosition)
        var wrong = RouteTracker()
        let progress = wrong.update(position: route.coordinates[2], timestamp: 1, route: route, heading: 180, carNavigation: true)
        XCTAssertNil(progress?.snappedPosition)
        XCTAssertGreaterThan(progress?.distanceFromRoute ?? 0, 35)
    }
    func testReplacementRequiresCurrentAccuratePositionOnCorrectCarRoute() {
        let route = route(), position = route.coordinates[1]
        XCTAssertNotNil(CarNavigation.replacement(route, origin: route.coordinates[0], requestedAt: 0, current: position, timestamp: 10, heading: 0, accuracy: 5, now: 10))
        XCTAssertNil(CarNavigation.replacement(route, origin: position, requestedAt: 0, current: position, timestamp: 60, heading: 0, accuracy: 5, now: 60))
        XCTAssertNil(CarNavigation.replacement(route, origin: position, requestedAt: 0, current: position, timestamp: 1, heading: 0, accuracy: 5, now: 10))
        XCTAssertNil(CarNavigation.replacement(route, origin: position, requestedAt: 0, current: position, timestamp: 10, heading: 180, accuracy: 5, now: 10))
    }
    func testLegacyProfilesKeepAbsentCarOptionsAndNewDataRoundTrips() throws {
        let data = Data(#"{"bike":"touring","electric":true,"surface":"any","gentleHills":false}"#.utf8)
        let old = try JSONDecoder().decode(RidingProfile.self, from: data)
        XCTAssertEqual(old.mode, .cycling); XCTAssertNil(old.carOptions)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("carOptions"))
        var car = old; car.mode = .car; car.carOptions = CarOptions(avoidHighways: true, avoidTolls: true)
        XCTAssertEqual(try JSONDecoder().decode(RidingProfile.self, from: JSONEncoder().encode(car)), car)
    }
}
