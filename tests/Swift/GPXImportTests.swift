import XCTest
@testable import BikeNaviCore

final class GPXImportTests: XCTestCase {
    private func fixture(_ name: String = "heidelberg-example") throws -> GPXFile {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try GPX.read(root.appendingPathComponent("fixtures/gpx/\(name).gpx"))
    }
    private func parse(_ xml: String) throws -> GPXFile { try GPX.parse(Data(xml.utf8)) }
    private func track(_ points: String) -> String { "<gpx version=\"1.1\"><trk><trkseg>\(points)</trkseg></trk></gpx>" }
    func testNamespacedTracksRoutesWaypointsAndSegments() throws {
        let file = try fixture()
        XCTAssertEqual(file.parts.map(\.kind), ["rte", "trk", "trk"])
        XCTAssertEqual(file.parts.map { $0.points.count }, [2, 4, 2])
        XCTAssertEqual(file.waypoints.count, 2)
        XCTAssertEqual(file.waypoints[0].details.name, "Beispiel: Pause & Aussicht")
        XCTAssertEqual(file.waypoints[0].details.time, "2026-10-21T08:00:00.125+02:00")
        XCTAssertTrue(file.ignoredExtensions)
        XCTAssertNil(file.parts[1].points[2].coordinate.altitude)
    }
    func testGPX10PrefixAndRouteRoundtrip() throws {
        let file = try fixture("route-1.0")
        let document = try file.document(part: 0, start: 0, end: 1, reversed: false)
        let output = try parse(GPX.xml(document))
        XCTAssertEqual(output.parts[0].kind, "rte")
        XCTAssertEqual(output.parts[0].points, file.parts[0].points)
        XCTAssertEqual(output.waypoints, file.waypoints)
    }
    func testFileRoundtripPreservesAllPointsAndSegmentBoundaries() throws {
        let file = try fixture()
        let output = try parse(GPX.xml(file))
        XCTAssertEqual(output.parts.map(\.points), file.parts.map(\.points))
        XCTAssertEqual(output.parts.map(\.name), file.parts.map(\.name))
        XCTAssertEqual(output.waypoints, file.waypoints)
    }
    func testSelectionReversalAndPlanRoundtrip() throws {
        let file = try fixture()
        let document = try file.document(part: 1, start: 1, end: 3, reversed: true)
        XCTAssertEqual(document.route?.coordinates, Array(file.parts[1].points[1...3].reversed()).map(\.coordinate))
        XCTAssertEqual(document.route?.gpxTrack?.points, Array(file.parts[1].points[1...3].reversed()).map(\.details))
        XCTAssertEqual(document.route?.gpxTrack?.waypoints, file.waypoints)
        let output = try parse(GPX.xml(document))
        XCTAssertEqual(output.parts[0].points, Array(file.parts[1].points[1...3].reversed()))
        XCTAssertEqual(output.waypoints, file.waypoints)
        XCTAssertTrue(document.route!.maneuvers.isEmpty)
        XCTAssertEqual(document.route!.coloredSections.first?.surface, 0)
    }
    func testLoopKeepsRepeatedStartAndOrder() throws {
        let file = try fixture()
        let route = try XCTUnwrap(file.document(part: 1, start: 0, end: 3, reversed: false).route)
        XCTAssertEqual(route.coordinates.first, route.coordinates.last)
        var tracker = RouteTracker(lastProgress: 0, lastTimestamp: 100)
        let start = try XCTUnwrap(tracker.update(position: route.coordinates[0], timestamp: 100, route: route))
        XCTAssertEqual(start.traveled, 0, accuracy: 0.01)
        XCTAssertGreaterThan(start.remaining, 200)
    }
    func testSmallLoopCanFinishWithoutJumpingBackToStart() throws {
        let file = try parse(track("<trkpt lat=\"49.4\" lon=\"8.7\"/><trkpt lat=\"49.401\" lon=\"8.7\"/><trkpt lat=\"49.401\" lon=\"8.701\"/><trkpt lat=\"49.4\" lon=\"8.7\"/>"))
        let route = try XCTUnwrap(file.document(part: 0, start: 0, end: 3, reversed: false).route)
        var tracker = RouteTracker(lastProgress: 0, lastTimestamp: 100)
        for index in 0..<3 {
            _ = tracker.update(position: route.coordinates[index], timestamp: 100 + Double(index) * 20, route: route)
        }
        let end = try XCTUnwrap(tracker.update(position: route.coordinates[3], timestamp: 160, route: route))
        XCTAssertEqual(end.remaining, 0, accuracy: 0.1)
    }
    func testSQLiteAndJSONRoundtripWithOldDocumentCompatibility() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture()
        let document = try file.document(part: 1, start: 0, end: 3, reversed: false)
        let url = folder.appendingPathComponent("test.sqlite")
        try LocalStore(url: url).save(document)
        var restored = try XCTUnwrap(LocalStore(url: url).all().first?.document)
        XCTAssertGreaterThanOrEqual(restored.updatedAt, document.updatedAt)
        restored.updatedAt = document.updatedAt
        XCTAssertEqual(restored, document)
        let encoded = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(TourDocument.self, from: encoded), document)
        var legacy = document; legacy.route?.gpxTrack = nil; legacy.route?.provider = "legacy"
        let oldData = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("gpxTrack"))
        XCTAssertNil(try JSONDecoder().decode(TourDocument.self, from: oldData).route?.gpxTrack)
    }
    func testWaypointsOnlyReadableButNotNavigable() throws {
        let file = try parse("<gpx><wpt lat=\"0\" lon=\"0\"><name>Nullinsel</name></wpt></gpx>")
        XCTAssertEqual(file.waypoints.count, 1)
        XCTAssertThrowsError(try file.document(part: 0, start: 0, end: 1, reversed: false))
        XCTAssertEqual(try parse(GPX.xml(file)).waypoints, file.waypoints)
    }
    func testMalformedAndOutOfRangeValuesFailAtomically() {
        for point in ["<trkpt lon=\"8\"/>", "<trkpt lat=\"NaN\" lon=\"8\"/>", "<trkpt lat=\"91\" lon=\"8\"/>",
                      "<trkpt lat=\"49\" lon=\"181\"/>", "<trkpt lat=\"49\" lon=\"8\"><ele>inf</ele></trkpt>",
                      "<trkpt lat=\"49\" lon=\"8\"><time>not-a-date</time></trkpt>"] {
            XCTAssertThrowsError(try parse(track("<trkpt lat=\"49\" lon=\"8\"/>" + point)))
        }
        for xml in ["", "<html/>", "<gpx>", "<gpx/>", "<gpx version=\"2.0\"/>", "<gpx xmlns=\"urn:other\"/>"] {
            XCTAssertThrowsError(try parse(xml))
        }
    }
    func testForeignNamespacesAndExtensionsCannotInjectPoints() throws {
        let xml = "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:x=\"urn:other\"><trk><trkseg><trkpt lat=\"49\" lon=\"8\"><x:ele>999</x:ele></trkpt><trkpt lat=\"49.1\" lon=\"8.1\"/><x:trkpt lat=\"0\" lon=\"0\"/></trkseg><extensions><trkseg><trkpt lat=\"0\" lon=\"0\"/></trkseg></extensions></trk></gpx>"
        let result = try parse(xml)
        XCTAssertEqual(result.parts.count, 1)
        XCTAssertEqual(result.parts[0].points.count, 2)
        XCTAssertNil(result.parts[0].points[0].coordinate.altitude)
    }
    func testEntitiesDepthTextAndFileSizeLimits() {
        XCTAssertThrowsError(try parse("<!DOCTYPE gpx [<!ENTITY e SYSTEM 'file:///does-not-exist'>]><gpx>&e;</gpx>"))
        XCTAssertThrowsError(try parse("<gpx>" + String(repeating: "<x>", count: 33) + String(repeating: "</x>", count: 33) + "</gpx>"))
        XCTAssertThrowsError(try parse("<gpx><name>" + String(repeating: "a", count: 16_385) + "</name></gpx>"))
        XCTAssertThrowsError(try GPX.parse(Data(repeating: 32, count: GPX.maximumBytes + 1)))
        XCTAssertThrowsError(try GPX.parse(Data([0xff, 0xfe])))
    }
    func testLargeTrackAndPointLimit() throws {
        let points = (0..<100_000).map { "<trkpt lat=\"49.4\" lon=\"\(8.6 + Double($0) * 0.000001)\"/>" }.joined()
        let file = try parse(track(points))
        XCTAssertEqual(file.parts[0].points.count, 100_000)
        let document = try file.document(part: 0, start: 0, end: 99_999, reversed: false)
        XCTAssertEqual(try parse(GPX.xml(document)).parts[0].points.count, 100_000)
        var tracker = RouteTracker()
        XCTAssertNotNil(tracker.update(position: document.route!.coordinates[100], timestamp: 1, route: document.route!))
        XCTAssertThrowsError(try parse(track(points + "<trkpt lat=\"49\" lon=\"8\"/>")))
    }
    func testInvalidSelectionAndZeroLength() throws {
        let file = try fixture()
        for (part, start, end) in [(-1, 0, 1), (99, 0, 1), (0, -1, 1), (0, 1, 0), (0, 0, 999)] {
            XCTAssertThrowsError(try file.document(part: part, start: start, end: end, reversed: false))
        }
        let zero = try parse(track(String(repeating: "<trkpt lat=\"49\" lon=\"8\"/>", count: 2)))
        XCTAssertThrowsError(try zero.document(part: 0, start: 0, end: 1, reversed: false))
    }
    func testRecordedRideExportStillUsesActualRecording() throws {
        var ride = try fixture().document(part: 1, start: 0, end: 3, reversed: false)
        ride.kind = .ride
        ride.track = [TrackPoint(coordinate: Coordinate(latitude: 48, longitude: 7, altitude: 80), timestamp: 1_700_000_000, accuracy: 5, speed: 3, segment: 1),
                      TrackPoint(coordinate: Coordinate(latitude: 48.1, longitude: 7.1), timestamp: 1_700_000_003, accuracy: 5, speed: 3, segment: 2)]
        let exported = try parse(GPX.xml(ride))
        XCTAssertEqual(exported.parts.count, 2)
        XCTAssertEqual(exported.parts.flatMap(\.points).map(\.coordinate), ride.track.map(\.coordinate))
    }
}
