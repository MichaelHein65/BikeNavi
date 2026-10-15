import XCTest
import CoreLocation
import UIKit
@testable import BikeNavi

private final class CarRouteProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    static var responseDelay: TimeInterval = 0
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "car-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            if Self.responseDelay > 0 { Thread.sleep(forTimeInterval: Self.responseDelay) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class CarRideTests: XCTestCase {
    @MainActor
    func testPOISearchInEveryModePreservesProfileAndActiveRide() throws {
        for mode in TravelMode.allCases {
            let (state, directory) = try state()
            defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
            state.plan.profile.mode = mode
            state.plan.route = nil
            let plan = state.plan
            let search = try state.poiSearch(category: .supermarket, duringRide: false, origin: "destination")
            XCTAssertEqual(search.profile, plan.profile)
            XCTAssertEqual(search.center, plan.destinationPoint?.coordinate)
            XCTAssertNil(search.context)
            fix(state, position: plan.waypoints[0].coordinate, timestamp: Date(), speed: 0)
            state.startRide()
            let ride = try XCTUnwrap(state.activeRide)
            let live = try state.poiSearch(category: .beach, duringRide: true)
            XCTAssertEqual(live.profile, ride.profile)
            XCTAssertEqual(live.center.distance(to: plan.waypoints[0].coordinate), 0, accuracy: 0.01)
            XCTAssertNil(live.context)
            state.savePlace(Waypoint(name: "Öffentliches POI-Beispiel", coordinate: search.center))
            XCTAssertEqual(state.activeRide, ride)
            XCTAssertEqual(state.plan, plan)
            XCTAssertTrue(state.savedPlaces.contains { $0.coordinate == search.center })
            state.discardRide()
        }
    }
    @MainActor
    private func state() throws -> (AppState, URL) {
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        setenv("BIKENAVI_SERVER", "", 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(store: try LocalStore(url: directory.appendingPathComponent("car.sqlite")))
        state.voice = false
        let points = (0...4).map { Coordinate(latitude: 49.414601 + Double($0) * 0.001, longitude: 8.681496) }
        var plan = TourDocument(); plan.title = "Öffentliche synthetische Pkw-Prüfung"; plan.profile.mode = .car
        plan.waypoints = [0, 2, 4].map { Waypoint(name: "Beispielpunkt", coordinate: points[$0]) }
        plan.route = CalculatedRoute(id: UUID(), coordinates: points, distance: 445, duration: 90, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [], provider: "Synthetisches Pkw-Beispiel", calculatedAt: 0,
            waypointIndices: [0, 2, 4], carTimeSections: [.init(startIndex: 0, endIndex: 4, seconds: 90)])
        state.plan = plan
        return (state, directory)
    }
    private func cleanup(_ directory: URL) {
        unsetenv("BIKENAVI_START_LOCATION_TEST"); unsetenv("BIKENAVI_SERVER")
        try? FileManager.default.removeItem(at: directory)
        CarRouteProtocol.handler = nil; CarRouteProtocol.responseDelay = 0; URLProtocol.unregisterClass(CarRouteProtocol.self)
    }
    @MainActor
    private func fix(_ state: AppState, position: Coordinate, timestamp: Date, speed: Double = 40) {
        state.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: position.cl,
            altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5, course: -1, speed: speed, timestamp: timestamp)])
    }
    @MainActor
    func testHighwayRecordingPauseRestoreAndFreeDriveNeverCaptureBikeData() throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan, points = plan.route!.coordinates, now = Date()
        fix(state, position: points[0], timestamp: now.addingTimeInterval(-4))
        state.startRide()
        let id = try XCTUnwrap(state.activeRide?.id)
        fix(state, position: points[2], timestamp: now)
        XCTAssertEqual(state.activeRide?.track.count, 2)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [2])
        state.recordBikeMeasurement(BikeMeasurement(bikeID: UUID(), timestamp: now.timeIntervalSince1970, batteryPercent: 50))
        XCTAssertEqual(try state.store.bikeSampleCounts(rideID: id).total, 0)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.profile.mode, .car)
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPendingWaypointOrdinals, [2])
        XCTAssertEqual(restored.ridingRoute?.id, plan.route?.id)
        XCTAssertEqual(restored.activeRide?.recordingState, .paused)
        restored.finishRide()
        XCTAssertEqual(try restored.store.all().first { $0.id == id }?.document.recordingState, .finished)
        XCTAssertEqual(state.plan, plan)
        // A free drive inherits the mode but no planned stops or route.
        state.discardRide(); state.plan.route = nil
        fix(state, position: points[0], timestamp: Date())
        state.startRide()
        XCTAssertEqual(state.activeRide?.profile.mode, .car)
        XCTAssertEqual(state.activeRide?.title, "Freie Autofahrt")
        XCTAssertNil(state.activeRide?.route)
        XCTAssertEqual(state.activeRide?.waypoints, [])
    }
    @MainActor
    func testAutomaticCarReroutePreservesStopsAndOriginalPlanAcrossRestart() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan, now = Date()
        fix(state, position: plan.route!.coordinates[0], timestamp: now.addingTimeInterval(-4))
        state.startRide()
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        let called = expectation(description: "Car route requested")
        CarRouteProtocol.handler = { call in
            let body: Data
            if let data = call.httpBody { body = data }
            else {
                let stream = try XCTUnwrap(call.httpBodyStream); stream.open(); defer { stream.close() }
                var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
                body = data
            }
            let request = try JSONDecoder().decode(RouteRequest.self, from: body)
            XCTAssertEqual(request.profile.mode, .car)
            XCTAssertEqual(Array(request.waypoints.dropFirst()), Array(plan.waypoints.dropFirst()))
            let points = request.waypoints.map(\.coordinate)
            let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 400, duration: 50, ascent: 0, descent: 0,
                maneuvers: [], surfaces: [], warnings: [], provider: "openrouteservice · Pkw", calculatedAt: 0,
                waypointIndices: [0, 1, 2], carTimeSections: [.init(startIndex: 0, endIndex: 2, seconds: 50)])
            called.fulfill()
            return try JSONEncoder().encode(route)
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        let off = Coordinate(latitude: plan.route!.coordinates[0].latitude, longitude: 8.683496)
        for seconds in [-2.0, 1.0, 3.0] { fix(state, position: off, timestamp: now.addingTimeInterval(seconds)) }
        await fulfillment(of: [called], timeout: 8)
        for _ in 0..<50 {
            if state.activeRide?.localNavigation?.carRoute != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let replacement = try XCTUnwrap(state.activeRide?.localNavigation?.carRoute)
        XCTAssertNotEqual(replacement.id, plan.route?.id)
        XCTAssertEqual(state.plan, plan)
        XCTAssertEqual(state.activeRide?.route?.id, plan.route?.id)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2])
        state.togglePause(); unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.ridingRoute?.id, replacement.id)
        XCTAssertEqual(restored.activeRide?.route?.id, plan.route?.id)
    }

    @MainActor
    func testPOIInsertionPreservesPlanTrackPendingStopsAndRestart() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan
        fix(state, position: plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01), speed: 0)
        let track = state.activeRide!.track
        let stop = Waypoint(name: "Synthetischer Tankstopp", coordinate: plan.route!.coordinates[1])
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.handler = { call in
            XCTAssertEqual(call.url?.path, "/v1/pois/route")
            let points = [plan.route!.coordinates[0], stop.coordinate] + plan.waypoints.dropFirst().map(\.coordinate)
            let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 445, duration: 120, ascent: 0, descent: 0,
                maneuvers: [], surfaces: [], warnings: [], provider: "Synthetische POI-Prüfung", calculatedAt: 0,
                waypointIndices: [0, 1, 2, 3], carTimeSections: [.init(startIndex: 0, endIndex: 3, seconds: 120)])
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(route))
            return try JSONSerialization.data(withJSONObject: ["route": encoded, "drivingDistance": 111, "drivingSeconds": 30, "detourSeconds": 30])
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        try await state.addPOIToRide(stop)
        XCTAssertEqual(state.plan, plan)
        XCTAssertEqual(state.activeRide?.track, track)
        XCTAssertEqual(state.activeRide?.waypoints.map(\.name), [plan.waypoints[0].name, stop.name, plan.waypoints[1].name, plan.waypoints[2].name])
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2, 3])
        XCTAssertEqual(state.activeRide?.localNavigation?.carPOIStopID, stop.id)
        XCTAssertNil(state.activeRide?.asNewPlan().route)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPOIStopID, stop.id)
        XCTAssertEqual(restored.ridingRoute?.id, state.ridingRoute?.id)
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2, 3])
        state.togglePause()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date(), speed: 0)
        CarRouteProtocol.handler = { call in
            guard call.url?.path == "/v1/route" else { throw URLError(.unsupportedURL) }
            return try JSONEncoder().encode(plan.route!)
        }
        try await state.removePOIStop()
        XCTAssertEqual(state.activeRide?.waypoints, plan.waypoints)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2])
        XCTAssertNil(state.pendingPOIStop)
        XCTAssertEqual(state.plan, plan)
    }

    @MainActor
    func testFailedPOIInsertionAndStaleGPSLeaveRideUnchanged() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        fix(state, position: state.plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: state.plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01))
        let before = state.activeRide
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        do {
            try await state.addPOIToRide(Waypoint(name: "Beispiel", coordinate: state.plan.route!.coordinates[1]))
            XCTFail("Anfahrt darf bei Netzfehler nicht übernommen werden")
        } catch { }
        XCTAssertEqual(state.activeRide, before)
        state.location.denied = true
        XCTAssertThrowsError(try state.poiSearch(category: .fuel, duringRide: true))
    }

    @MainActor
    func testPOIResponseCannotReplaceRideAfterPause() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan
        fix(state, position: plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01), speed: 0)
        let called = expectation(description: "POI request started")
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.responseDelay = 0.3
        CarRouteProtocol.handler = { call in
            guard call.url?.path == "/v1/pois/route" else { throw URLError(.unsupportedURL) }
            called.fulfill()
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.route!))
            return try JSONSerialization.data(withJSONObject: ["route": encoded, "drivingDistance": 111, "drivingSeconds": 30])
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        let request = Task { try await state.addPOIToRide(Waypoint(name: "Beispiel", coordinate: plan.route!.coordinates[1])) }
        await fulfillment(of: [called], timeout: 5)
        state.togglePause()
        let paused = state.activeRide
        do { try await request.value; XCTFail("Verspätete Antwort darf die pausierte Fahrt nicht ersetzen") } catch { }
        XCTAssertEqual(state.activeRide, paused)
        XCTAssertEqual(state.plan, plan)
    }
}
