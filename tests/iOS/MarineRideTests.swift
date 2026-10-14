import XCTest
import CoreLocation
import UIKit
@testable import BikeNavi

final class MarineRideTests: XCTestCase {
    @MainActor
    func testSeaRideRecordsOnlyGPSAndRestoresCurrentCoursePoint() throws {
        setenv("BIKENAVI_SERVER", "", 1)
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        defer { unsetenv("BIKENAVI_SERVER"); unsetenv("BIKENAVI_START_LOCATION_TEST"); UIApplication.shared.isIdleTimerDisabled = false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalStore(url: directory.appendingPathComponent("sea.sqlite"))
        let state = AppState(store: store)
        var plan = TourDocument()
        plan.profile.mode = .sea
        plan.title = "Tribunj · synthetische GPS-Prüfung"
        let coordinates = [Coordinate(latitude: 43.7508, longitude: 15.7458), Coordinate(latitude: 43.7508, longitude: 15.7463), Coordinate(latitude: 43.7508, longitude: 15.7468)]
        plan.waypoints = [Waypoint(name: "Beispielstart", coordinate: coordinates[0]), Waypoint(name: "Beispielziel", coordinate: coordinates[2])]
        plan.route = CalculatedRoute(id: UUID(), coordinates: coordinates, distance: 80, duration: 0, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [MarineNavigation.warning], provider: "Seeweg · OSM-Wasserwege", calculatedAt: 0, waypointIndices: [0, 2])
        plan.route?.marineRoutingRevision = MarineNavigation.routingRevision
        plan.route?.marineDraft = 2
        plan.route?.marineDepthSource = "Synthetischer Test"
        state.plan = plan
        let now = Date()
        func fix(_ index: Int, age: Double) {
            state.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: coordinates[index].cl,
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, course: 90, speed: 3, timestamp: now.addingTimeInterval(-age))])
        }
        fix(0, age: 4)
        state.plan.route?.marineRoutingRevision = nil
        state.startRide()
        XCTAssertNil(state.activeRide)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertEqual(state.plan.route?.id, plan.route?.id)
        state.plan.route?.marineRoutingRevision = MarineNavigation.routingRevision
        state.errorMessage = nil
        state.startRide()
        let id = try XCTUnwrap(state.activeRide?.id)
        XCTAssertTrue(state.isMarinePresentation)
        XCTAssertEqual(state.marineTargetIndex, 1)
        XCTAssertNil(state.progress)
        fix(1, age: 0)
        XCTAssertEqual(state.marineTargetIndex, 2)
        XCTAssertEqual(state.activeRide?.track.count, 2)
        state.recordBikeMeasurement(BikeMeasurement(bikeID: UUID(), timestamp: now.timeIntervalSince1970, batteryPercent: 50))
        XCTAssertEqual(try store.bikeSampleCounts(rideID: id).total, 0)
        state.selectedMapStyle = .standard
        XCTAssertTrue(state.isMarinePresentation)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: store)
        restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.id, id)
        XCTAssertEqual(restored.activeRide?.profile.mode, .sea)
        XCTAssertEqual(restored.marineTargetIndex, 2)
        XCTAssertEqual(restored.selectedMapStyle, .seamap)
        XCTAssertNil(restored.progress)
        // A ready cycling plan must replace a paused sea ride with cycling behavior.
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        var cycling = plan
        cycling.id = UUID()
        cycling.profile.mode = .cycling
        cycling.route?.id = UUID()
        cycling.route?.provider = "Synthetische Radprüfung"
        restored.plan = cycling
        restored.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: coordinates[0].cl,
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, course: 90, speed: 3, timestamp: Date())])
        restored.openRide()
        XCTAssertEqual(restored.activeRide?.profile.mode, .cycling)
        XCTAssertEqual(restored.activeRide?.route?.id, cycling.route?.id)
        XCTAssertEqual(restored.selectedMapStyle, .standard)
        XCTAssertFalse(restored.isMarinePresentation)
        XCTAssertEqual(try store.all().first { $0.id == id }?.document.recordingState, .finished)
    }

    @MainActor
    func testBoatSettingsPersistAcrossAppStateAndRejectInvalidValues() throws {
        let defaults = UserDefaults.standard
        let keys = ["boatDraft", "boatSpeedKnots", "showWaterDepths"]
        let original = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, original) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        keys.forEach { defaults.removeObject(forKey: $0) }
        setenv("BIKENAVI_SERVER", "", 1)
        defer { unsetenv("BIKENAVI_SERVER") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(url: directory.appendingPathComponent("settings.sqlite"))
        let state = AppState(store: store)
        XCTAssertEqual(state.boatDraft, 2)
        XCTAssertEqual(state.boatSpeedKnots, 4)
        state.boatDraft = 2.7; state.boatSpeedKnots = 5.5; state.showWaterDepths = true
        let restored = AppState(store: store)
        XCTAssertEqual(restored.boatDraft, 2.7)
        XCTAssertEqual(restored.boatSpeedKnots, 5.5)
        XCTAssertTrue(restored.showWaterDepths)
        restored.boatDraft = 0; restored.boatSpeedKnots = .nan
        XCTAssertEqual(restored.boatDraft, 2.7)
        XCTAssertEqual(restored.boatSpeedKnots, 5.5)
    }

    @MainActor
    func testBikeCommunicationCannotStartWhileMarineModeIsSuspended() {
        let bike = BikeBluetoothService()
        bike.setSuspended(true)
        bike.monitor(true, for: .rideScreen)
        bike.monitor(true, for: .activeRide)
        bike.monitor(true, for: .diagnostics)
        XCTAssertTrue(bike.suspended)
        XCTAssertFalse(bike.running)
        XCTAssertFalse(bike.connected)
        bike.monitor(false, for: .rideScreen)
        bike.monitor(false, for: .activeRide)
        bike.monitor(false, for: .diagnostics)
        bike.setSuspended(false)
        XCTAssertFalse(bike.running)
    }
}
