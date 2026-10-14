import XCTest
import CoreLocation
import UIKit
@testable import BikeNavi

final class ApplicationHomeTests: XCTestCase {
    @MainActor
    private func withState(_ check: (AppState, URL) throws -> Void) throws {
        let keys = ["currentPlan", "serverURL", "token", "voice"] + TravelMode.homeModes.map { "applicationPlan." + $0.rawValue }
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1); setenv("BIKENAVI_SERVER", "", 1)
        defer {
            unsetenv("BIKENAVI_START_LOCATION_TEST"); unsetenv("BIKENAVI_SERVER")
            for key in keys { if let value = saved[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
            try? FileManager.default.removeItem(at: folder)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        let state = AppState(store: try LocalStore(url: folder.appendingPathComponent("home.sqlite")))
        state.voice = false
        try check(state, folder)
        state.discardRide()
    }
    @MainActor
    func testEveryTileCreatesOwnPlanAndDefaultMapWithoutModeSwitchInAppearance() throws {
        try withState { state, _ in
            XCTAssertNil(state.applicationMode)
            for mode in TravelMode.homeModes {
                state.chooseApplication(mode)
                XCTAssertEqual(state.applicationMode, mode)
                XCTAssertEqual(state.plan.profile.mode, mode)
                XCTAssertEqual(state.selectedMapStyle, mode == .sea ? .seamap : mode == .hiking ? .topographic : .standard)
                XCTAssertEqual(state.applicationMapStyles.contains(.seamap), mode == .sea)
                state.selectedMapStyle = .satellite
                XCTAssertEqual(state.plan.profile.mode, mode)
                XCTAssertEqual(state.workspaceSupportsBike, mode.supportsBike)
                state.returnToHome()
                XCTAssertNil(state.applicationMode)
            }
        }
    }
    @MainActor
    func testDraftsPreferencesAndChosenPlanSurviveHomeAndRestart() throws {
        try withState { state, _ in
            state.chooseApplication(.car)
            state.renamePlan(to: "Auto · öffentliches Speicherbeispiel")
            state.plan.profile.carOptions = .init(avoidHighways: true, avoidTolls: true, avoidFerries: false)
            let carID = state.plan.id
            state.returnToHome(); state.chooseApplication(.hiking)
            state.renamePlan(to: "Wandern · öffentliches Speicherbeispiel")
            let hikeID = state.plan.id
            state.returnToHome(); state.chooseApplication(.car)
            XCTAssertEqual(state.plan.id, carID)
            XCTAssertEqual(state.plan.profile.drivingOptions.avoidHighways, true)
            state.newPlan()
            let newer = state.plan.id
            XCTAssertNotEqual(newer, carID)
            XCTAssertEqual(state.plan.profile.mode, .car)
            XCTAssertTrue(state.plan.profile.drivingOptions.avoidHighways)
            state.resetPlan()
            XCTAssertEqual(state.plan.id, newer)
            XCTAssertTrue(state.plan.profile.drivingOptions.avoidTolls)
            state.returnToHome()
            unsetenv("BIKENAVI_START_LOCATION_TEST")
            let restored = AppState(store: state.store)
            XCTAssertNil(restored.applicationMode)
            restored.chooseApplication(.hiking)
            XCTAssertEqual(restored.plan.id, hikeID)
            restored.returnToHome(); restored.chooseApplication(.car)
            XCTAssertEqual(restored.plan.id, newer)
        }
    }
    @MainActor
    func testRecordingAndPausedRideRemainUntouchedAcrossApplicationsAndExplicitResume() throws {
        try withState { state, _ in
            state.chooseApplication(.hiking)
            let fix = CLLocation(coordinate: .init(latitude: 49.414601, longitude: 8.681496), altitude: 114,
                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
            state.location.locationManager(CLLocationManager(), didUpdateLocations: [fix])
            state.startRide()
            let id = try XCTUnwrap(state.activeRide?.id)
            XCTAssertEqual(state.activeRide?.title, "Freie Wanderung")
            state.returnToHome(); state.chooseApplication(.sea)
            state.openRide(); state.startRide()
            XCTAssertTrue(state.hasConflictingApplicationRide)
            XCTAssertEqual(state.activeRide?.id, id)
            XCTAssertEqual(state.activeRide?.recordingState, .recording)
            XCTAssertFalse(state.isMarinePresentation)
            state.recordBikeMeasurement(.init(bikeID: UUID(), timestamp: Date().timeIntervalSince1970, batteryPercent: 50))
            XCTAssertEqual(try state.store.bikeSampleCounts(rideID: id).total, 0)
            state.resumeApplicationRide(); state.openRide()
            XCTAssertEqual(state.applicationMode, .hiking)
            XCTAssertEqual(state.tab, 1)
            XCTAssertEqual(state.activeRide?.id, id)
            XCTAssertTrue(state.isWalkingSection)
            state.togglePause()
            state.returnToHome(); state.chooseApplication(.car); state.openRide()
            XCTAssertEqual(state.activeRide?.id, id)
            XCTAssertEqual(state.activeRide?.recordingState, .paused)
            state.resumeApplicationRide(); state.openRide()
            XCTAssertEqual(state.activeRide?.id, id)
            XCTAssertEqual(state.activeRide?.recordingState, .paused)
            state.finishRide()
            XCTAssertEqual(try state.store.all().first { $0.id == id }?.document.recordingState, .finished)
        }
    }
    @MainActor
    func testCombinedTourStopsNewBikeMeasurementsAtWalkingTransition() throws {
        try withState { state, _ in
            let waypoints = state.plan.waypoints
            var route = try XCTUnwrap(state.plan.route)
            route.walkingStartIndex = 1
            state.chooseApplication(.bikeAndHike)
            state.plan.waypoints = waypoints; state.plan.route = route
            let fix = CLLocation(coordinate: waypoints[0].coordinate.cl, altitude: 114,
                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
            state.location.locationManager(CLLocationManager(), didUpdateLocations: [fix])
            state.startRide()
            let id = try XCTUnwrap(state.activeRide?.id), bikeID = UUID(), time = Date().timeIntervalSince1970
            XCTAssertFalse(state.isWalkingSection)
            state.recordBikeMeasurement(.init(bikeID: bikeID, timestamp: time, batteryPercent: 50))
            XCTAssertEqual(try state.store.bikeSampleCounts(rideID: id).total, 1)
            state.progress = RouteProgress(traveled: LocalRouteMetrics.distances(route)[1], remaining: 0,
                distanceFromRoute: 0, nextManeuver: nil, distanceToManeuver: 0)
            XCTAssertTrue(state.isWalkingSection)
            state.recordBikeMeasurement(.init(bikeID: bikeID, timestamp: time + 1, batteryPercent: 49))
            XCTAssertEqual(try state.store.bikeSampleCounts(rideID: id).total, 1)
        }
    }
    @MainActor
    func testDeletingCurrentDraftRetainsApplicationAndPreferences() throws {
        try withState { state, _ in
            state.chooseApplication(.car)
            state.plan.profile.carOptions = .init(avoidHighways: true, avoidTolls: false, avoidFerries: false)
            state.savePlan()
            let record = try XCTUnwrap(state.currentRecord)
            state.delete(record)
            XCTAssertEqual(state.applicationMode, .car)
            XCTAssertEqual(state.plan.profile.mode, .car)
            XCTAssertTrue(state.plan.profile.drivingOptions.avoidHighways)
            XCTAssertNotEqual(state.plan.id, record.id)
        }
    }

}
