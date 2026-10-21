import XCTest
import CoreLocation
import UIKit
@testable import BikeNavi

private final class GPXNoNetwork: URLProtocol {
    static var requests: [String] = []
    static var legacyServer = false
    static var uploadedGPX = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url?.path ?? "unknown")
        if Self.legacyServer {
            do {
                let data: Data
                switch request.url?.path {
                case "/v1/status": data = Data("{\"routingAvailable\":false,\"version\":\"0.4.0\"}".utf8)
                case "/v1/changes": data = Data("{\"records\":[],\"cursor\":0,\"hasMore\":false}".utf8)
                case "/v1/mutations":
                    var body = request.httpBody ?? Data()
                    if body.isEmpty, let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var buffer = [UInt8](repeating: 0, count: 4096)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            guard count > 0 else { break }
                            body.append(contentsOf: buffer.prefix(count))
                        }
                    }
                    let mutation = try JSONDecoder().decode(Mutation.self, from: body)
                    Self.uploadedGPX = Self.uploadedGPX || mutation.document.route?.isGPXTrack == true
                    data = try JSONEncoder().encode(RemoteRecord(document: mutation.document, revision: 1, deleted: false))
                default: throw URLError(.unsupportedURL)
                }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
            return
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

final class GPXNavigationTests: XCTestCase {
    private func sample() throws -> TourDocument {
        let xml = """
        <gpx version="1.1"><wpt lat="49.4148" lon="8.682"><name>Beispielpause</name></wpt>
        <trk><name>Synthetische GPX-Testspur</name><trkseg>
        <trkpt lat="49.4146" lon="8.6815"><time>2026-10-21T06:00:00Z</time></trkpt>
        <trkpt lat="49.4150" lon="8.6820"/><trkpt lat="49.4155" lon="8.6830"/>
        </trkseg></trk></gpx>
        """
        return try GPX.parse(Data(xml.utf8)).document(part: 0, start: 0, end: 2, reversed: false)
    }
    @MainActor
    func testOldBackendKeepsGPXLocalWhileSyncingOtherPlans() async throws {
        let keys = ["currentPlan", "serverURL", "token", "voice"] + TravelMode.homeModes.map { "applicationPlan." + $0.rawValue }
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        setenv("BIKENAVI_SERVER", "", 1); setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        GPXNoNetwork.legacyServer = true; GPXNoNetwork.uploadedGPX = false; GPXNoNetwork.requests = []
        URLProtocol.registerClass(GPXNoNetwork.self)
        defer {
            GPXNoNetwork.legacyServer = false; URLProtocol.unregisterClass(GPXNoNetwork.self)
            unsetenv("BIKENAVI_SERVER"); unsetenv("BIKENAVI_START_LOCATION_TEST")
            for key in keys { if let value = saved[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
            try? FileManager.default.removeItem(at: folder)
        }
        let store = try LocalStore(url: folder.appendingPathComponent("sync.sqlite"))
        let state = AppState(store: store)
        let previousID = state.plan.id
        let imported = try sample()
        let source = folder.appendingPathComponent("valid.gpx")
        try GPX.xml(imported).write(to: source, atomically: true, encoding: .utf8)
        await state.readGPX(source)
        XCTAssertNotNil(state.gpxImport)
        XCTAssertEqual(state.plan.id, previousID, "Reading must not replace the current plan")
        state.importGPX(imported)
        state.serverURL = "https://gpx-test.invalid"; state.token = String(repeating: "a", count: 40)
        await state.sync()
        XCTAssertTrue(try XCTUnwrap(store.record(id: imported.id)).dirty)
        XCTAssertFalse(try XCTUnwrap(store.record(id: previousID)).dirty)
        XCTAssertFalse(GPXNoNetwork.uploadedGPX)
        XCTAssertTrue(GPXNoNetwork.requests.contains("/v1/mutations"))
        XCTAssertTrue(state.notice?.contains("GPX-Update") == true)
    }
    @MainActor
    func testImportReversePersistFollowDeviationAndResumeWithoutNetwork() async throws {
        let keys = ["currentPlan", "serverURL", "token", "voice"] + TravelMode.homeModes.map { "applicationPlan." + $0.rawValue }
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        setenv("BIKENAVI_SERVER", "", 1)
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        GPXNoNetwork.requests = []
        URLProtocol.registerClass(GPXNoNetwork.self)
        defer {
            URLProtocol.unregisterClass(GPXNoNetwork.self)
            unsetenv("BIKENAVI_SERVER"); unsetenv("BIKENAVI_START_LOCATION_TEST")
            for key in keys { if let value = saved[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
            UIApplication.shared.isIdleTimerDisabled = false
            try? FileManager.default.removeItem(at: folder)
        }
        let store = try LocalStore(url: folder.appendingPathComponent("test.sqlite"))
        let state = AppState(store: store)
        state.voice = false
        let previous = state.plan
        let document = try sample()
        state.importGPX(document)
        XCTAssertEqual(state.plan.route, document.route)
        XCTAssertNotNil(try store.record(id: previous.id))
        XCTAssertEqual(state.applicationMode, .cycling)
        state.reversePlan()
        XCTAssertEqual(state.plan.route?.coordinates, Array(document.route!.coordinates.reversed()))
        XCTAssertEqual(state.plan.route?.gpxTrack?.points, Array(document.route!.gpxTrack!.points.reversed()))
        state.reversePlan()
        let preserved = state.plan.route
        state.serverURL = "https://gpx-test.invalid"; state.token = String(repeating: "a", count: 40)
        state.prepareLocalRouting(refresh: true)
        state.loadPlanElevation()
        state.invalidateRoute()
        await state.calculateRoute()
        XCTAssertEqual(state.plan.route, preserved)
        XCTAssertFalse(state.preparingLocalRouting)
        XCTAssertFalse(state.loadingElevation)
        state.addPoint(Waypoint(name: "Nicht übernehmen", coordinate: Coordinate(latitude: 0, longitude: 0)), role: .destination)
        state.useCurrentLocation()
        XCTAssertEqual(state.plan.route, preserved)
        state.errorMessage = nil
        let now = Date()
        func fix(lat: Double, lon: Double, seconds: Double) {
            state.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 114,
                horizontalAccuracy: 5, verticalAccuracy: 5, course: 45, speed: 3, timestamp: now.addingTimeInterval(seconds))])
        }
        fix(lat: 49.4146, lon: 8.6815, seconds: -4)
        state.startRide()
        let rideID = try XCTUnwrap(state.activeRide?.id)
        XCTAssertEqual(state.activeRide?.sourcePlanID, document.id)
        for offset in [-3.0, 0, 3] { fix(lat: 49.42, lon: 8.69, seconds: offset) }
        XCTAssertNil(state.errorMessage, "Location updates must not keep trying to replace the GPX start")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(state.rerouting)
        XCTAssertEqual(state.activeRide?.route, preserved)
        XCTAssertEqual(state.ridingRoute, preserved)
        XCTAssertTrue(state.localRideStatus?.contains("Abseits") == true)
        XCTAssertTrue(GPXNoNetwork.requests.isEmpty, GPXNoNetwork.requests.description)
        state.serverURL = ""
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: store)
        restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.id, rideID)
        XCTAssertEqual(restored.activeRide?.recordingState, .paused)
        XCTAssertEqual(restored.activeRide?.route, preserved)
        XCTAssertEqual(restored.ridingRoute, preserved)
        XCTAssertEqual(restored.activeRide?.route?.gpxTrack?.waypoints.count, 1)
        restored.finishRide()
        XCTAssertEqual(try store.record(id: rideID)?.document.recordingState, .finished)
    }
    @MainActor
    func testImportDoesNotReplaceActiveRideAndInvalidFileDoesNotChangePlan() async throws {
        let keys = ["currentPlan", "serverURL", "token", "voice"] + TravelMode.homeModes.map { "applicationPlan." + $0.rawValue }
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        setenv("BIKENAVI_SERVER", "", 1)
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            unsetenv("BIKENAVI_SERVER"); unsetenv("BIKENAVI_START_LOCATION_TEST")
            for key in keys { if let value = saved[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
            UIApplication.shared.isIdleTimerDisabled = false
            try? FileManager.default.removeItem(at: folder)
        }
        let state = AppState(store: try LocalStore(url: folder.appendingPathComponent("test.sqlite")))
        state.voice = false
        state.plan.route = nil
        state.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: .init(latitude: 49.4146, longitude: 8.6815),
            altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())])
        state.startRide()
        let ride = try XCTUnwrap(state.activeRide)
        state.importGPX(try sample())
        XCTAssertEqual(state.activeRide, ride)
        let plan = state.plan
        let broken = folder.appendingPathComponent("broken.gpx")
        try Data("<gpx><broken>".utf8).write(to: broken)
        await state.readGPX(broken)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertNil(state.gpxImport)
        XCTAssertEqual(state.plan, plan)
        XCTAssertEqual(state.activeRide, ride)
        state.finishRide()
    }
}
