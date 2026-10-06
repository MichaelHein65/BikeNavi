import XCTest
@testable import BikeNaviCore

final class RouteElevationTests: XCTestCase {
    func route(_ metres: [Double] = [0, 300]) -> CalculatedRoute {
        let coordinates = metres.map { Coordinate(latitude: 49, longitude: 8 + $0 / (111_320 * cos(49 * .pi / 180))) }
        var route = CalculatedRoute(id: UUID(), coordinates: coordinates, distance: 0, duration: 60,
            ascent: 0, descent: 0, maneuvers: [Maneuver(instruction: "Ziel", distance: 0, coordinateIndex: coordinates.count-1, type: 10)],
            surfaces: [], warnings: ["Höhenwerte und Fahrzeit sind lokal nur eingeschränkt verfügbar.", "Zugang prüfen"],
            provider: "BikeNavi iPhone · OpenStreetMap", calculatedAt: 1,
            surfaceSections: [RouteSurfaceSection(startIndex: 0, endIndex: coordinates.count-1, surface: 3)],
            waypointIndices: [0, coordinates.count-1])
        route.distance = LocalRouteMetrics.distances(route).last!
        return route
    }

    func testSamplingIncludesHillsInsideLongEdgesAndPreservesEndpoints() throws {
        let original = route()
        let sampling = try RouteElevation.sample(original)
        XCTAssertGreaterThan(sampling.coordinates.count, 8)
        XCTAssertEqual(sampling.coordinates.first, original.coordinates.first)
        XCTAssertEqual(sampling.coordinates.last, original.coordinates.last)
        XCTAssertEqual(sampling.distances.last!, original.distance, accuracy: 0.001)
        for (a, b) in zip(sampling.distances, sampling.distances.dropFirst()) {
            XCTAssertGreaterThan(b-a, 0); XCTAssertLessThanOrEqual(b-a, 30.001)
        }
        let heights = sampling.distances.map { 100 + min($0, original.distance-$0) / 3 }
        let updated = try RouteElevation.applying(ElevationResponse(altitudes: heights, source: "Test DEM"), sampling: sampling, to: original)
        XCTAssertGreaterThan(updated.ascent, 35)
        XCTAssertEqual(updated.ascent, updated.descent, accuracy: 0.001)
        XCTAssertGreaterThan(updated.elevationSamples.count, updated.coordinates.count)
        XCTAssertEqual(updated.coordinates.map(\.latitude), original.coordinates.map(\.latitude))
        XCTAssertEqual(updated.coordinates.map(\.longitude), original.coordinates.map(\.longitude))
        XCTAssertEqual(updated.maneuvers, original.maneuvers)
        XCTAssertEqual(updated.surfaceSections, original.surfaceSections)
        XCTAssertEqual(updated.waypointIndices, original.waypointIndices)
        XCTAssertEqual(updated.distance, original.distance)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertTrue(updated.hasElevation)
        XCTAssertEqual(updated.warnings, ["Zugang prüfen"])
    }

    func testProviderLimitAndDuplicateVertices() throws {
        let sampling = try RouteElevation.sample(route([0, 0, 10, 200_000, 200_000]))
        XCTAssertEqual(sampling.coordinates.count, 2000)
        XCTAssertTrue(sampling.distances.allSatisfy(\.isFinite))
        XCTAssertThrowsError(try RouteElevation.sample(route([0, 0])))
    }

    func testInvalidResponsesCannotBecomeZeroHeightProfiles() throws {
        let original = route(), sampling = try RouteElevation.sample(route())
        for value in [Double.nan, .infinity, -32768, 9001] {
            var heights = Array(repeating: 10.0, count: sampling.coordinates.count); heights[1] = value
            XCTAssertThrowsError(try RouteElevation.applying(ElevationResponse(altitudes: heights, source: "Test"), sampling: sampling, to: original))
        }
        XCTAssertThrowsError(try RouteElevation.applying(ElevationResponse(altitudes: [0, 0], source: "Test"), sampling: sampling, to: original))
        var changed = original; changed.coordinates[0].latitude += 1
        XCTAssertThrowsError(try RouteElevation.applying(ElevationResponse(altitudes: Array(repeating: 0, count: sampling.coordinates.count), source: "Test"), sampling: sampling, to: changed))
        XCTAssertFalse(original.hasElevation)
    }

    func testFlatSeaLevelAndNegativeHeightsAreValid() throws {
        for altitude in [0.0, -20.0] {
            let original = route(), sampling = try RouteElevation.sample(route())
            let updated = try RouteElevation.applying(ElevationResponse(altitudes: Array(repeating: altitude, count: sampling.coordinates.count), source: "Test DEM"), sampling: sampling, to: original)
            XCTAssertTrue(updated.hasElevation)
            XCTAssertEqual(updated.ascent, 0); XCTAssertEqual(updated.descent, 0)
            XCTAssertTrue(updated.elevationSamples.allSatisfy { $0.altitude == altitude })
        }
    }

    func testGradualSlopesAndNoiseThreshold() {
        func samples(_ heights: [Double]) -> [RouteElevationSample] {
            heights.enumerated().map { RouteElevationSample(distance: Double($0.offset)*30, altitude: $0.element) }
        }
        XCTAssertEqual(RouteElevation.totals(samples([0, 1, 2, 3, 4, 5])).ascent, 5)
        let noise = RouteElevation.totals(samples([10, 11, 9, 10, 11, 10]))
        XCTAssertEqual(noise.ascent, 0); XCTAssertEqual(noise.descent, 0)
        let valley = RouteElevation.totals(samples([20, 15, 10, 5, 0, 5, 10]))
        XCTAssertEqual(valley.ascent, 10); XCTAssertEqual(valley.descent, 20)
    }

    func testProfileSurvivesLocalSaveReopenAndGPXExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var document = TourDocument()
        let original = route(), sampling = try RouteElevation.sample(route())
        document.route = try RouteElevation.applying(ElevationResponse(altitudes: Array(repeating: 42, count: sampling.coordinates.count), source: "Test DEM"), sampling: sampling, to: original)
        let database = directory.appendingPathComponent("tours.sqlite")
        try LocalStore(url: database).save(document)
        let reopened = try XCTUnwrap(LocalStore(url: database).record(id: document.id)).document
        XCTAssertEqual(reopened.route, document.route)
        XCTAssertTrue(GPX.xml(reopened).contains("<ele>42.0</ele>"))
        // Legacy payloads have neither optional field and remain readable.
        let legacy = try JSONDecoder().decode(CalculatedRoute.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.elevationProfile); XCTAssertFalse(legacy.hasElevation)
    }

    func testReturnConnectorDoesNotReuseOriginalElevationTotals() throws {
        let original = route(), sampling = try RouteElevation.sample(route())
        let elevated = try RouteElevation.applying(ElevationResponse(altitudes: sampling.distances.map { $0/3 }, source: "Test"), sampling: sampling, to: original)
        let connector = route([-100, 0])
        let combined = LocalRouteMetrics.combined(original: elevated, state: LocalNavigationState(connector: connector, rejoinIndex: 0))
        XCTAssertFalse(combined.hasElevation)
        XCTAssertNil(combined.elevationProfile)
        XCTAssertEqual(combined.ascent, 0)
        XCTAssertNotNil(elevated.elevationProfile)
    }
}
