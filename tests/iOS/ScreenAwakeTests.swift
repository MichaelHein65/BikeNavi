import XCTest
import UIKit
@testable import BikeNavi

final class ScreenAwakeTests: XCTestCase {
    @MainActor
    func testNavigationKeepsScreenAwakeAcrossViewsAndForegroundTransitions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            try? FileManager.default.removeItem(at: directory)
        }
        let state = AppState(store: try LocalStore(url: directory.appendingPathComponent("test.sqlite")))
        state.updateScreenAwake(sceneActive: true)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        var ride = TourDocument()
        ride.kind = .ride
        ride.recordingState = .recording
        state.activeRide = ride
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        state.tab = 2
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        state.updateScreenAwake(sceneActive: false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        state.updateScreenAwake(sceneActive: true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        // Reapply even when UIKit resets the flag without a ride-state change.
        UIApplication.shared.isIdleTimerDisabled = false
        state.updateScreenAwake(sceneActive: true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        state.activeRide?.recordingState = .paused
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        state.activeRide?.recordingState = .recording
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        state.activeRide = nil
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }
}
