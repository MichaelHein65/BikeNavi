import XCTest
import CoreLocation
import UIKit
@testable import BikeNavi

final class FreeRideTests: XCTestCase {
    @MainActor
    func testFreeRideRecordsPausesRestoresAndFinishesWithoutChangingPlan() throws {
        setenv("BIKENAVI_SERVER", "", 1)
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        defer {
            unsetenv("BIKENAVI_START_LOCATION_TEST")
            unsetenv("BIKENAVI_SERVER")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try LocalStore(url: directory.appendingPathComponent("test.sqlite"))
        let state = AppState(store: store)
        // An incomplete plan must not become the route or waypoints of a free ride.
        state.plan.route = nil
        state.plan.waypoints = [state.plan.waypoints[0]]
        let plan = state.plan
        let now = Date()
        func fix(_ longitude: Double, seconds: Double) {
            let sample = CLLocation(coordinate: .init(latitude: 49.414601, longitude: longitude),
                                    altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5,
                                    course: 90, speed: 3, timestamp: now.addingTimeInterval(seconds))
            state.location.locationManager(CLLocationManager(), didUpdateLocations: [sample])
        }
        fix(8.681496, seconds: -12)
        state.openRide()
        let id = try XCTUnwrap(state.activeRide?.id)
        XCTAssertEqual(state.activeRide?.title, "Freie Fahrt")
        XCTAssertNil(state.activeRide?.route)
        XCTAssertNil(state.activeRide?.sourcePlanID)
        XCTAssertNil(state.activeRide?.localNavigation)
        XCTAssertEqual(state.activeRide?.waypoints, [])
        XCTAssertNil(state.progress)
        XCTAssertNil(state.localRideStatus)
        XCTAssertEqual(state.activeRide?.track.count, 1)
        state.openRide()
        XCTAssertEqual(state.activeRide?.id, id)
        fix(8.681696, seconds: -8)
        XCTAssertEqual(state.activeRide?.track.count, 2)
        XCTAssertGreaterThan(state.activeRide?.recordedDistance ?? 0, 10)
        XCTAssertEqual(state.activeRide?.movingDuration, 4)
        state.togglePause()
        fix(8.681896, seconds: -4)
        XCTAssertEqual(state.activeRide?.track.count, 2)
        state.togglePause()
        fix(8.682096, seconds: 0)
        XCTAssertEqual(state.activeRide?.track.count, 3)
        XCTAssertEqual(state.activeRide?.track.last?.segment, 2)
        XCTAssertEqual(state.activeRide?.movingDuration, 4)
        XCTAssertEqual(state.plan, plan)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: store)
        XCTAssertEqual(restored.activeRide?.id, id)
        XCTAssertEqual(restored.activeRide?.recordingState, .paused)
        XCTAssertEqual(restored.activeRide?.track.count, 3)
        XCTAssertNil(restored.activeRide?.route)
        restored.finishRide()
        XCTAssertNil(restored.activeRide)
        let saved = try XCTUnwrap(restored.records.first { $0.id == id }?.document)
        XCTAssertEqual(saved.recordingState, .finished)
        XCTAssertEqual(saved.track.count, 3)
        XCTAssertNotNil(saved.endedAt)
        XCTAssertNil(saved.sourcePlanID)
    }
}
