import XCTest
@testable import BikeNaviCore

final class MarineNavigationTests: XCTestCase {
    private func point(_ latitude: Double, _ longitude: Double) -> Waypoint {
        Waypoint(name: "Öffentlicher Beispielpunkt", coordinate: Coordinate(latitude: latitude, longitude: longitude))
    }
    func testRhumbCoursesCardinalDirectionsAndDateline() throws {
        let origin = point(0, 0)
        XCTAssertEqual(MarineNavigation.leg(from: origin, to: point(1, 0)).course, 0, accuracy: 1e-9)
        XCTAssertEqual(MarineNavigation.leg(from: origin, to: point(0, 1)).course, 90, accuracy: 1e-9)
        XCTAssertEqual(MarineNavigation.leg(from: origin, to: point(-1, 0)).course, 180, accuracy: 1e-9)
        XCTAssertEqual(MarineNavigation.leg(from: origin, to: point(0, -1)).course, 270, accuracy: 1e-9)
        let dateline = MarineNavigation.leg(from: point(0, 179.9), to: point(0, -179.9))
        XCTAssertEqual(dateline.course, 90, accuracy: 1e-9)
        XCTAssertEqual(dateline.distance, 22238.9853, accuracy: 0.1)
    }
    func testOnlyCoastCheckedRoutesSupplySteeringPoints() {
        let points = [point(43.75, 15.75), point(43.74, 15.77)]
        var document = TourDocument()
        document.profile.mode = .sea
        document.waypoints = points
        document.route = CalculatedRoute(id: UUID(), coordinates: [points[0].coordinate, Coordinate(latitude: 43.745, longitude: 15.765), points[1].coordinate],
            distance: 2000, duration: 0, ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [],
            provider: "Seeweg · OSM-Wasserwege", calculatedAt: 0, waypointIndices: [0, 2])
        let navigation = MarineNavigation.navigationPoints(document)
        XCTAssertEqual(navigation.count, 3)
        XCTAssertEqual(navigation.last?.name, points[1].name)
        XCTAssertEqual(MarineNavigation.legs(navigation).count, 2)
        document.route?.provider = "Ungeprüfte Kurslinien"
        XCTAssertTrue(MarineNavigation.navigationPoints(document).isEmpty)
        XCTAssertTrue(MarineNavigation.legs([point(.nan, 0), point(0, 0)]).isEmpty)
    }
    func testSeaRoutingNeverFallsBackToUncheckedOfflineLines() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineRoutingStore(directory: directory)
        var document = TourDocument()
        document.profile.mode = .sea
        document.waypoints = [point(43.75, 15.75), point(43.73, 15.88)]
        do {
            _ = try await store.calculate(document: document, api: nil) { _, _ in }
            XCTFail("Sea routing must require coast data")
        } catch {
            XCTAssertTrue(error is MarineNavigation.Failure)
        }
    }
    func testCourseOverGroundRequiresMovementAndFreshAccurateGPS() {
        func course(speed: Double = 3, timestamp: Double = 100, accuracy: Double = 5, heading: Double = 135) -> Double? {
            MarineNavigation.cog(course: heading, speed: speed, timestamp: timestamp, accuracy: accuracy, now: 100)
        }
        XCTAssertEqual(course(), 135)
        XCTAssertNil(course(speed: 0))
        XCTAssertNil(course(timestamp: 94.9))
        XCTAssertNil(course(timestamp: 102))
        XCTAssertNil(course(accuracy: 51))
        XCTAssertNil(course(heading: -1))
        XCTAssertNil(course(heading: .nan))
    }
    func testOnlyCurrentWaypointCanAdvanceAndInvalidFixesNeverSkipIt() {
        let points = [point(43.75, 15.75), point(43.74, 15.77), point(43.73, 15.80)]
        func next(position: Coordinate, accuracy: Double = 5, timestamp: Double = 100) -> Int {
            MarineNavigation.nextWaypoint(current: 1, points: points, position: position, accuracy: accuracy, timestamp: timestamp, now: 100)
        }
        XCTAssertEqual(next(position: points[1].coordinate), 2)
        XCTAssertEqual(next(position: points[2].coordinate), 1)
        XCTAssertEqual(next(position: points[1].coordinate, accuracy: 40), 1)
        XCTAssertEqual(next(position: points[1].coordinate, timestamp: 90), 1)
        XCTAssertEqual(MarineNavigation.nextWaypoint(current: 2, points: points, position: points[2].coordinate, accuracy: 5, timestamp: 100, now: 100), 3)
    }
    func testNauticalUnitsAndCoordinateMinuteRollover() {
        XCTAssertEqual(MarineNavigation.distance(1852), "1,0 sm")
        XCTAssertEqual(MarineNavigation.distance(150), "0,08 sm")
        XCTAssertEqual(MarineNavigation.speed(1852 / 3600), "1,0 kn")
        XCTAssertEqual(MarineNavigation.course(359.9), "000°")
        XCTAssertEqual(MarineNavigation.position(Coordinate(latitude: 43.9999999, longitude: -15.75)), "44° 00.00′ N   15° 45.00′ W")
    }
    func testRemainingDistanceETAAndNoShortcutAcrossCourseChanges() throws {
        let points = [point(43.75,15.75),point(43.75,15.76),point(43.74,15.76)]
        let remaining = try XCTUnwrap(MarineNavigation.remainingDistance(points: points, target: 1, position: points[0].coordinate))
        XCTAssertEqual(remaining, MarineNavigation.legs(points).reduce(0) { $0 + $1.distance }, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(MarineNavigation.travelTime(distance: 4*1852, speedKnots: 4)), 3600, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MarineNavigation.travelTime(distance: 4*1852, speedKnots: 8)), 1800, accuracy: 0.001)
        XCTAssertNil(MarineNavigation.remainingDistance(points: points, target: 1, position: points[2].coordinate))
        XCTAssertEqual(MarineNavigation.remainingDistance(points: points, target: 3, position: points[2].coordinate), 0)
        XCTAssertNil(MarineNavigation.travelTime(distance: 100, speedKnots: 0))
        XCTAssertEqual(MarineNavigation.setting(0, range: 0.1...20, fallback: 2), 2)
        XCTAssertEqual(MarineNavigation.setting(.nan, range: 0.5...50, fallback: 4), 4)
        XCTAssertEqual(MarineNavigation.setting(2.7, range: 0.1...20, fallback: 2), 2.7)
    }

    func testBoatSettingInputAllowsCommaOrPointAndRejectsIncompleteOrInvalidNumbers() {
        for text in ["2", "2,0", "2.0", " 2,0 "] {
            XCTAssertEqual(MarineNavigation.settingInput(text, range: 0.1...20), 2)
        }
        XCTAssertEqual(MarineNavigation.settingInput("0,1", range: 0.1...20), 0.1)
        XCTAssertEqual(MarineNavigation.settingInput("20", range: 0.1...20), 20)
        XCTAssertEqual(MarineNavigation.settingInput("5.5", range: 0.5...50), 5.5)
        for text in ["", "0", "0,", "2,", "21", "-2", "NaN", "inf", "2m", "2,5.0", "1e1"] {
            XCTAssertNil(MarineNavigation.settingInput(text, range: 0.1...20), text)
        }
    }

}
