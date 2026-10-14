import XCTest
@testable import BikeNaviCore

final class ApplicationWorkspaceTests: XCTestCase {
    func testTileOrderAndCapabilities() {
        XCTAssertEqual(TravelMode.homeModes, [.cycling, .car, .hiking, .bikeAndHike, .sea])
        XCTAssertEqual(TravelMode.homeModes.map(\.homeTitle), ["Fahrrad", "Auto", "Wandern", "Fahrrad & Wandern", "Segeln"])
        XCTAssertEqual(TravelMode.homeModes.filter(\.supportsBike), [.cycling, .bikeAndHike])
        XCTAssertEqual(TravelMode.bikeAndHike.homeAsset, "HomeBikeAndHike")
    }
    func testNewAndResetPlanKeepOnlyMatchingApplicationPreferences() {
        var profile = RidingProfile(); profile.mode = .car
        profile.carOptions = .init(avoidHighways: true, avoidTolls: true, avoidFerries: false)
        let fresh = ApplicationWorkspace.newPlan(mode: .car, profile: profile)
        XCTAssertEqual(fresh.profile, profile)
        XCTAssertNil(fresh.route)
        XCTAssertTrue(fresh.waypoints.isEmpty)
        XCTAssertNil(ApplicationWorkspace.newPlan(mode: .hiking, profile: profile).profile.carOptions)
        XCTAssertEqual(ApplicationWorkspace.newPlan(mode: .sea).profile.mode, .sea)
    }
    func testOwnCurrentDraftWinsWithoutConvertingAnotherRoute() {
        let current = ApplicationWorkspace.newPlan(mode: .hiking)
        let saved = SavedRecord(document: ApplicationWorkspace.newPlan(mode: .hiking))
        XCTAssertEqual(ApplicationWorkspace.plan(mode: .hiking, current: current, records: [saved], preferredID: saved.id), current)
        let car = ApplicationWorkspace.plan(mode: .car, current: current, records: [saved], preferredID: current.id)
        XCTAssertEqual(car.profile.mode, .car)
        XCTAssertNotEqual(car.id, current.id)
        XCTAssertNil(car.route)
    }
    func testPreferredThenLatestNondeletedPlanExcludesRideAndOtherApplication() {
        let current = ApplicationWorkspace.newPlan(mode: .cycling)
        var preferred = ApplicationWorkspace.newPlan(mode: .car); preferred.updatedAt = 1
        var latest = ApplicationWorkspace.newPlan(mode: .car); latest.updatedAt = 2
        var deleted = ApplicationWorkspace.newPlan(mode: .car); deleted.updatedAt = 4
        var ride = ApplicationWorkspace.newPlan(mode: .car); ride.kind = .ride; ride.updatedAt = 5
        let records = [SavedRecord(document: preferred), SavedRecord(document: latest), SavedRecord(document: deleted, deleted: true), SavedRecord(document: ride)]
        XCTAssertEqual(ApplicationWorkspace.plan(mode: .car, current: current, records: records, preferredID: preferred.id), preferred)
        XCTAssertEqual(ApplicationWorkspace.plan(mode: .car, current: current, records: records, preferredID: deleted.id), latest)
        XCTAssertEqual(ApplicationWorkspace.plan(mode: .car, current: current, records: records, preferredID: ride.id), latest)
    }
}
