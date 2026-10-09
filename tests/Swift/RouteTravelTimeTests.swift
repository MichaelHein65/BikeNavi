import XCTest
@testable import BikeNaviCore

final class RouteTravelTimeTests: XCTestCase {
    private func route() -> CalculatedRoute {
        CalculatedRoute(id: UUID(), coordinates: [.init(latitude: 49, longitude: 8), .init(latitude: 49.001, longitude: 8), .init(latitude: 49.002, longitude: 8)],
            distance: 2000, duration: 1, ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [], provider: "synthetic", calculatedAt: 0,
            surfaceSections: [.init(startIndex: 0, endIndex: 1, surface: 3), .init(startIndex: 1, endIndex: 2, surface: 10)])
    }
    func testAgreedSpeedsAndMixedSurfaceTimeIgnoreOptimisticProviderDuration() {
        let estimate = RouteTravelTime(route: route(), profile: RidingProfile())
        XCTAssertEqual(estimate.total, 180 + 300, accuracy: 0.001)
        XCTAssertEqual(RouteTravelTime.speedKPH(surface: .paving, walking: false), 16)
        XCTAssertEqual(RouteTravelTime.speedKPH(surface: .natural, walking: false), 8)
        XCTAssertEqual(RouteTravelTime.speedKPH(surface: .unknown, walking: false), 12)
    }
    func testRemainingTimeUsesOnlyUnriddenSurfaceAndClimb() {
        var route = route()
        route.coordinates[0].altitude = 0
        route.coordinates[1].altitude = 60
        route.coordinates[2].altitude = 60
        route.ascent = 60
        let estimate = RouteTravelTime(route: route, profile: RidingProfile())
        XCTAssertEqual(estimate.total, 840, accuracy: 0.001)
        let firstLeg = route.coordinates[0].distance(to: route.coordinates[1])
        XCTAssertEqual(estimate.remaining(after: firstLeg), 300, accuracy: 0.001)
        XCTAssertEqual(estimate.remaining(after: firstLeg / 2), 570, accuracy: 0.001)
        XCTAssertEqual(estimate.remaining(after: 10000), 0)
        XCTAssertEqual(estimate.remaining(after: -100), estimate.total)
    }
    func testUnknownSurfaceAndMissingElevationsUseConservativeFallback() {
        var route = route()
        route.surfaceSections = nil
        route.ascent = 60
        let estimate = RouteTravelTime(route: route, profile: RidingProfile())
        XCTAssertEqual(estimate.total, 600 + 360, accuracy: 0.001)
    }
    func testWalkingTransitionAndFullHikingUseWalkingSpeed() {
        var route = route()
        route.walkingStartIndex = 1
        XCTAssertEqual(RouteTravelTime(route: route, profile: RidingProfile()).total, 180 + 900, accuracy: 0.001)
        var profile = RidingProfile()
        profile.mode = .hiking
        XCTAssertEqual(RouteTravelTime(route: route, profile: profile).total, 1800, accuracy: 0.001)
    }
    func testDownhillAndDegenerateGeometryDoNotInventHighSpeedOrInvalidTime() {
        var route = route()
        route.coordinates[0].altitude = 100
        route.coordinates[1].altitude = 80
        route.coordinates[2].altitude = 60
        XCTAssertEqual(RouteTravelTime(route: route, profile: RidingProfile()).total, 480, accuracy: 0.001)
        route.coordinates = [route.coordinates[0], route.coordinates[0]]
        route.surfaceSections = nil
        XCTAssertEqual(RouteTravelTime(route: route, profile: RidingProfile()).total, 0)
        route.coordinates = []
        XCTAssertEqual(RouteTravelTime(route: route, profile: RidingProfile()).total, 0)
    }
}
