import XCTest
@testable import BikeNaviCore

final class POITests: XCTestCase {
    func testDiscoveryDecodesAirDistanceAndKeepsOriginalCoordinate() throws {
        let data = Data("""
        {"id":"example","name":"Beispielstrand","coordinate":{"latitude":49.411,"longitude":8.68},
         "country":"DE","address":"Beispiel","source":"Geoapify · OSM","sourceURL":"https://www.geoapify.com/places-api/",
         "fetchedAt":100,"airDistance":750,"drivingDistance":0,"drivingSeconds":0}
        """.utf8)
        let place = try JSONDecoder().decode(POIPlace.self, from: data)
        XCTAssertEqual(place.airDistance, 750)
        XCTAssertEqual(place.waypoint.coordinate.latitude, 49.411)
        XCTAssertNil(place.detourSeconds)
    }
    func testProviderArrivalContractUsesDrivableCoordinateInExistingClient() throws {
        let data = Data("""
        {"id":"example","name":"Beispielbahnhof","coordinate":{"latitude":49.41,"longitude":8.68},
         "placeCoordinate":{"latitude":49.411,"longitude":8.68},"accessDistance":111,
         "arrivalCoordinate":{"latitude":49.41,"longitude":8.68},"country":"DE",
         "address":"Pkw-Zielpunkt: 111 m Luftlinie; Fußweg nicht berechnet.",
         "source":"Geoapify · OSM","sourceURL":"https://www.geoapify.com/places-api/",
         "fetchedAt":100,"drivingDistance":1000,"drivingSeconds":100}
        """.utf8)
        let place = try JSONDecoder().decode(POIPlace.self, from: data)
        XCTAssertEqual(place.waypoint.coordinate.latitude, 49.41)
        XCTAssertTrue(place.address.contains("Fußweg nicht berechnet"))
        XCTAssertNil(place.isOpen)
        XCTAssertNil(place.dieselPrice)
    }

    func testLegacyNavigationStillDecodesAndNewStopForcesFreshPlanRoute() throws {
        let navigation = try JSONDecoder().decode(LocalNavigationState.self, from: Data("{\"originalProgress\":0,\"usedUnpaved\":0,\"routeProgress\":0}".utf8))
        XCTAssertNil(navigation.carPOIStopID)
        var ride = TourDocument()
        ride.localNavigation = navigation
        ride.localNavigation?.carPOIStopID = UUID()
        let first = Coordinate(latitude: 49.41, longitude: 8.68)
        ride.route = CalculatedRoute(id: UUID(), coordinates: [first, Coordinate(latitude: 49.42, longitude: 8.68)],
            distance: 1000, duration: 100, ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [], provider: "Example", calculatedAt: 0)
        XCTAssertNil(ride.asNewPlan().route)
        XCTAssertNotNil(ride.route)
    }
}
