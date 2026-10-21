import XCTest
import MapLibre
@testable import BikeNavi

@MainActor private final class LocalStyleDelegate: NSObject, MLNMapViewDelegate {
    var loaded: XCTestExpectation
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) { loaded.fulfill() }
    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) { XCTFail(error.localizedDescription) }
}
final class RegionalMapTests: XCTestCase {
    @MainActor
    func testLocalRegionStyleLoadsWithoutRemoteResources() async throws {
        let a = Coordinate(latitude: 49, longitude: 8), b = Coordinate(latitude: 49.001, longitude: 8.001)
        let id = OfflineTileID.at(a)
        let tile = OfflineGraphTile(version: 1,x: id.x,y: id.y,generatedAt: 1,compilerRevision: 3,
            nodes: [OfflineGraphNode(id: 1,coordinate: a),OfflineGraphNode(id: 2,coordinate: b)],
            edges: [OfflineGraphEdge(from: 1,to: 2,way: 1,surface: 3,name: "Beispielweg",incline: 0)],restrictions: [])
        let data = try OfflineRegionStore.mapStyle(OfflineGraph(tiles: [tile],regional: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["glyphs"]); XCTAssertNil(object["sprite"])
        let sources = try XCTUnwrap(object["sources"] as? [String: [String: Any]])
        XCTAssertEqual(sources.count, 1); XCTAssertEqual(sources["roads"]?["type"] as? String, "geojson")
        XCTAssertNil(sources["roads"]?["url"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let loaded = expectation(description: "Local MapLibre style")
        let delegate = LocalStyleDelegate(loaded)
        let map = MLNMapView(frame: CGRect(x: 0,y: 0,width: 390,height: 400), styleURL: url)
        map.delegate = delegate
        map.setCenter(a.cl, zoomLevel: 14, animated: false)
        await fulfillment(of: [loaded], timeout: 10)
        XCTAssertNotNil(map.style?.source(withIdentifier: "roads"))
        map.delegate = nil
    }
}
