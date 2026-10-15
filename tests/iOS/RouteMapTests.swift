import XCTest
import MapLibre
@testable import BikeNavi

final class RouteMapTests: XCTestCase {
    @MainActor
    func testPOIOverviewSurvivesInitialStyleFitAndPreservesManualZoom() throws {
        let (map, coordinator) = try fixture()
        let place = Waypoint(name: "Öffentliches POI-Beispiel", coordinate: .init(latitude: 49.41, longitude: 8.68))
        coordinator.parent.route = nil
        coordinator.parent.navigationPosition = nil
        coordinator.parent.waypoints = [place]
        coordinator.parent.focus = place.coordinate
        coordinator.parent.pointOverviewZoom = 14
        coordinator.hasLoadedStyle = false
        map.setCenter(place.coordinate.cl, zoomLevel: 19, animated: false)
        coordinator.mapView(map, didFinishLoading: try XCTUnwrap(map.style))
        XCTAssertEqual(map.zoomLevel, 14, accuracy: 0.01)
        XCTAssertEqual(map.centerCoordinate.latitude, place.coordinate.latitude, accuracy: 0.00001)
        XCTAssertEqual(map.centerCoordinate.longitude, place.coordinate.longitude, accuracy: 0.00001)
        map.setZoomLevel(15, animated: false)
        coordinator.redraw()
        coordinator.mapView(map, didFinishLoading: try XCTUnwrap(map.style))
        XCTAssertEqual(map.zoomLevel, 15, accuracy: 0.01)
        coordinator.fit()
        XCTAssertEqual(map.zoomLevel, 14, accuracy: 0.01)
        map.delegate = nil
    }
    @MainActor
    func testCarCameraChangesScaleAndManualExplorationOffersExplicitResume() throws {
        let (map, coordinator) = try fixture()
        coordinator.parent.carNavigation = true
        coordinator.parent.follow = true
        coordinator.parent.followHeading = true
        coordinator.parent.navigationHeading = 0
        coordinator.parent.navigationLookAhead = 350
        coordinator.parent.navigationProgress = 0
        coordinator.updateNavigationCamera()
        let cityAltitude = map.camera.altitude
        coordinator.parent.navigationLookAhead = 1600
        coordinator.updateNavigationCamera()
        // The city frame may already widen to include the curved approach.
        XCTAssertGreaterThan(map.camera.altitude, cityAltitude * 1.3)
        coordinator.mapView(map, regionWillChangeWith: .gesturePinch, animated: false)
        XCTAssertTrue(coordinator.navigationSuspended)
        let held = map.camera.altitude
        coordinator.parent.navigationLookAhead = 200
        coordinator.updateNavigationCamera()
        XCTAssertEqual(map.camera.altitude, held)
        coordinator.resetNavigationInteraction()
        coordinator.updateNavigationCamera()
        XCTAssertFalse(coordinator.navigationSuspended)
        XCTAssertLessThan(map.camera.altitude, held)
        map.delegate = nil
    }
    @MainActor
    func testMarineCameraUsesRawPositionAndKeepsNorthUpAndUserZoom() throws {
        let (map, coordinator) = try fixture()
        map.setZoomLevel(14, animated: false)
        coordinator.parent.marineNavigation = true
        coordinator.parent.follow = true
        coordinator.parent.navigationHeading = 135
        coordinator.parent.navigationPosition = Coordinate(latitude: 43.7508, longitude: 15.7458)
        coordinator.updateNavigationCamera()
        XCTAssertEqual(map.camera.pitch, 0, accuracy: 0.001)
        XCTAssertEqual(map.camera.heading, 0, accuracy: 0.001)
        XCTAssertEqual(map.centerCoordinate.latitude, 43.7508, accuracy: 0.000001)
        XCTAssertEqual(map.zoomLevel, 14, accuracy: 0.001)
        coordinator.mapView(map, regionWillChangeWith: .gesturePan, animated: false)
        XCTAssertTrue(coordinator.navigationSuspended)
        coordinator.parent.navigationPosition?.latitude += 0.001
        coordinator.updateNavigationCamera()
        XCTAssertEqual(map.centerCoordinate.latitude, 43.7508, accuracy: 0.000001)
        coordinator.resetNavigationInteraction()
        coordinator.updateNavigationCamera()
        XCTAssertEqual(map.centerCoordinate.latitude, 43.7518, accuracy: 0.000001)
        map.delegate = nil
    }
    @MainActor
    private func fixture() throws -> (MLNMapView, RouteMap.Coordinator) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("map-test-\(UUID()).json")
        try Data(##"{"version":8,"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#ffffff"}}]}"##.utf8).write(to: url)
        let coordinates = [Coordinate(latitude: 49.41, longitude: 8.68),
                           Coordinate(latitude: 49.411, longitude: 8.681),
                           Coordinate(latitude: 49.412, longitude: 8.682)]
        let route = CalculatedRoute(id: UUID(), coordinates: coordinates, distance: 300, duration: 100,
            ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [], provider: "synthetic test", calculatedAt: 0,
            surfaceSections: [.init(startIndex: 0, endIndex: 1, surface: 3), .init(startIndex: 1, endIndex: 2, surface: 10)])
        let parent = RouteMap(styleURL: url.absoluteString, route: route,
            waypoints: [.init(name: "Beispielstart", coordinate: coordinates[0]), .init(name: "Beispielziel", coordinate: coordinates[2])],
            navigationPosition: coordinates[0], colorBySurface: true)
        let coordinator = parent.makeCoordinator()
        let map = MLNMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 500), styleURL: url)
        coordinator.map = map
        map.delegate = coordinator
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in coordinator.hasLoadedStyle }, object: map)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        try FileManager.default.removeItem(at: url)
        return (map, coordinator)
    }

    @MainActor
    func testIndependentDepthLayerSurvivesStyleReloadAndToggleWithoutLosingRoute() throws {
        let (map, coordinator) = try fixture()
        let count = map.annotations?.count
        coordinator.parent.showWaterDepths = true
        coordinator.updateWaterDepths()
        XCTAssertNotNil(map.style?.source(withIdentifier: "emodnet-depth"))
        XCTAssertEqual(map.style?.layer(withIdentifier: "emodnet-depth")?.isVisible, true)
        XCTAssertEqual(map.viewWithTag(71304)?.isHidden, false)
        coordinator.parent.showWaterDepths = false
        coordinator.updateWaterDepths()
        XCTAssertEqual(map.style?.layer(withIdentifier: "emodnet-depth")?.isVisible, false)
        XCTAssertEqual(map.annotations?.count, count)
        coordinator.parent.showWaterDepths = true
        coordinator.mapView(map, didFinishLoading: try XCTUnwrap(map.style))
        XCTAssertEqual(map.style?.layer(withIdentifier: "emodnet-depth")?.isVisible, true)
        XCTAssertEqual(map.annotations?.count, count)
        map.delegate = nil
    }

    @MainActor
    func testRecordingUpdatesKeepRouteAndPositionAnnotationsAttached() throws {
        let (map, coordinator) = try fixture()
        let original = try XCTUnwrap(map.annotations)
        let routeLines = original.compactMap { $0 as? MLNPolyline }
        XCTAssertEqual(routeLines.count, 2)
        for sample in 0..<100 {
            let coordinate = Coordinate(latitude: 49.41 + Double(sample) * 0.00001, longitude: 8.68)
            coordinator.parent.track.append(TrackPoint(coordinate: coordinate, timestamp: Double(sample), accuracy: 5, speed: 4, segment: 0))
            coordinator.parent.navigationPosition = coordinate
            coordinator.redraw()
            // Check before the position update: recording must not remove the pin either.
            for annotation in original {
                XCTAssertTrue(map.annotations?.contains { ($0 as AnyObject) === (annotation as AnyObject) } == true)
            }
            coordinator.updateNavigationPosition()
        }
        XCTAssertEqual(map.annotations?.compactMap { $0 as? MLNPolyline }.filter { $0.title == "track" }.count, 1)
        XCTAssertEqual(coordinator.navigationPin.coordinate.latitude, 49.41099, accuracy: 0.000001)
        map.delegate = nil
    }

    @MainActor
    func testGeometryChangeWithSameRouteIDAndRouteRemovalReplaceOnlyRoute() throws {
        let (map, coordinator) = try fixture()
        let pin = coordinator.navigationPin
        let oldLines = try XCTUnwrap(map.annotations).compactMap { $0 as? MLNPolyline }
        coordinator.parent.route?.coordinates[1].longitude += 0.001
        coordinator.redraw()
        XCTAssertFalse(map.annotations?.contains { current in oldLines.contains { (current as AnyObject) === $0 } } == true)
        XCTAssertTrue(map.annotations?.contains { ($0 as AnyObject) === pin } == true)
        XCTAssertEqual(map.annotations?.compactMap { $0 as? MLNPolyline }.count, 2)
        coordinator.parent.route = nil
        coordinator.redraw()
        XCTAssertEqual(map.annotations?.compactMap { $0 as? MLNPolyline }.count, 0)
        XCTAssertTrue(map.annotations?.contains { ($0 as AnyObject) === pin } == true)
        map.delegate = nil
    }

    @MainActor
    func testStyleRefreshRestoresRouteWithoutDuplicateAnnotations() throws {
        let (map, coordinator) = try fixture()
        // Simulate the renderer losing registered overlays during a style reload.
        map.removeAnnotations(try XCTUnwrap(map.annotations))
        coordinator.redraw(force: true)
        coordinator.updateNavigationPosition()
        XCTAssertEqual(map.annotations?.compactMap { $0 as? MLNPolyline }.count, 2)
        XCTAssertEqual(map.annotations?.count, 5)
        coordinator.redraw(force: true)
        coordinator.updateNavigationPosition()
        XCTAssertEqual(map.annotations?.count, 5)
        map.delegate = nil
    }
}
