import XCTest
@testable import BikeNaviCore

final class RegionalNavigationTests: XCTestCase {
    func point(_ x: Double, _ y: Double = 0) -> Coordinate {
        Coordinate(latitude: 49+y/111320, longitude: 8+x/(111320*cos(49 * .pi/180)))
    }
    func tile(id: OfflineTileID, length: Double = 1000) -> OfflineGraphTile {
        OfflineGraphTile(version: 1, x: id.x, y: id.y, generatedAt: 1, compilerRevision: 3,
            nodes: [OfflineGraphNode(id: 1, coordinate: point(0)), OfflineGraphNode(id: 2, coordinate: point(length))],
            edges: [OfflineGraphEdge(from: 1, to: 2, way: 1, surface: 3, name: "Öffentliches synthetisches Beispiel", incline: 0, roadClass: "cycleway", cycleway: true, inclineKnown: true)], restrictions: [])
    }
    func package(_ tile: OfflineGraphTile) throws -> RegionTilePackage {
        let data = try JSONEncoder().encode(tile)
        return RegionTilePackage(schema: 1, bytes: data.count, sha256: RegionTilePackage.hash(data), data: data)
    }
    func document() -> TourDocument {
        var result = TourDocument()
        result.waypoints = [Waypoint(name: "Beispielstart", coordinate: point(10)), Waypoint(name: "Beispielziel", coordinate: point(990))]
        return result
    }
    func testIndependentRegionDownloadOfflineRestartUpdateFailureAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineRegionStore(directory: directory)
        let id = OfflineTileID.at(point(0)), package = try package(tile(id: id))
        let region = try await store.download(name: "Öffentliches Beispiel", tiles: [id], fetch: { _, _ in package }, progress: { _, _ in })
        let restarted = OfflineRegionStore(directory: directory)
        let graph = try await restarted.graph(region)
        let route = try LocalRouter.plan(graph: graph, document: document())
        XCTAssertEqual(route.distance, 980, accuracy: 2)
        XCTAssertTrue(graph.regional)
        let routing = OfflineRoutingStore(directory: directory.appendingPathComponent("corridor"), regions: restarted)
        let offline = try await routing.calculate(document: document(), api: nil, progress: { _, _ in })
        XCTAssertEqual(offline.distance, route.distance, accuracy: 0.1)
        var saved = document(); saved.profile.cyclePreference = .quiet; saved.route = offline
        let database = try LocalStore(url: directory.appendingPathComponent("test.sqlite"))
        try database.save(saved)
        let restored = try XCTUnwrap(database.record(id: saved.id)).document
        XCTAssertEqual(restored.profile.cyclePreference, .quiet)
        XCTAssertEqual(restored.route?.cycleQuality, offline.cycleQuality)
        let styleURL = try await restarted.styleURL(region)
        let style = try String(contentsOf: styleURL)
        XCTAssertFalse(style.contains("glyphs")); XCTAssertFalse(style.contains("sprite"))
        XCTAssertTrue(style.contains("FeatureCollection"))
        do {
            var corrupt = package; corrupt.data = Data("bad".utf8)
            let immutable = corrupt
            _ = try await restarted.download(name: "Update", tiles: [id], refresh: true, fetch: { _, _ in immutable }, progress: { _, _ in })
            XCTFail("Corrupt update accepted")
        } catch { }
        let retained = try await restarted.list()
        XCTAssertEqual(retained, [region])
        _ = try await restarted.graph(region)
        try await restarted.delete(region)
        let empty = try await restarted.list()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: styleURL.path))
    }
    func testResumeAtVerifiedChunkAndMissingFileFailsClosed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineRegionStore(directory: directory)
        let first = OfflineTileID.at(point(0)), second = OfflineTileID(x: first.x+1, y: first.y)
        let a = try package(tile(id: first))
        var empty = tile(id: second); empty.edges = []; empty.nodes = []
        let b = try package(empty)
        do {
            _ = try await store.download(name: "Beispiel", tiles: [first,second], fetch: { id, _ in
                if id == second { throw URLError(.notConnectedToInternet) }; return a
            }, progress: { _, _ in })
            XCTFail()
        } catch { }
        let pending = try await store.pendingDownloads(); XCTAssertEqual(pending, 1)
        let region = try await store.download(name: "Beispiel", tiles: [first,second], fetch: { id, _ in
            if id == first { XCTFail("Verified chunk downloaded twice") }; return b
        }, progress: { _, _ in })
        try FileManager.default.removeItem(at: directory.appendingPathComponent(a.sha256 + ".json"))
        do { _ = try await store.graph(region); XCTFail() } catch { }
    }
    func testDiscardInterruptedReplacementPreservesCompletedRegion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineRegionStore(directory: directory)
        let id = OfflineTileID.at(point(0)), second = OfflineTileID(x: id.x+1,y: id.y)
        let package = try package(tile(id: id))
        let completed = try await store.download(name: "Beispiel", tiles: [id], fetch: { _, _ in package }, progress: { _, _ in })
        do {
            _ = try await store.download(name: "Größeres Beispiel", tiles: [id,second], fetch: { tile, _ in
                if tile == second { throw CancellationError() }; return package
            }, progress: { _, _ in })
            XCTFail()
        } catch { }
        let pending = try await store.pendingDownloads(); XCTAssertEqual(pending, 1)
        try await store.discardPendingDownloads()
        let cleared = try await store.pendingDownloads(); XCTAssertEqual(cleared, 0)
        let regions = try await store.list(); XCTAssertEqual(regions, [completed])
        _ = try await store.graph(completed)
    }
    func testBudgetAndBounds() async throws {
        XCTAssertThrowsError(try OfflineRegion.tiles(center: point(0), radius: 3))
        XCTAssertEqual(try OfflineRegion.tiles(center: point(0), radius: 2).count, 25)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = OfflineTileID.at(point(0)), data = try package(tile(id: id))
        let store = OfflineRegionStore(directory: directory, budget: 20)
        do { _ = try await store.download(name: "Beispiel", tiles: [id], fetch: { _, _ in data }, progress: { _, _ in }); XCTFail() } catch RegionError.space { }
        let regions = try await store.list(); XCTAssertTrue(regions.isEmpty)
    }
    func testRegionalRejoinBeyondThreeKilometres() throws {
        let id = OfflineTileID.at(point(0)); var tile = tile(id: id, length: 6000)
        // Intermediate node keeps matching bins small and the geometry connected.
        tile.nodes.insert(OfflineGraphNode(id: 3, coordinate: point(3000)), at: 1)
        tile.edges = [OfflineGraphEdge(from: 1,to: 3,way: 1,surface: 3,name: "Beispiel",incline: 0), OfflineGraphEdge(from: 3,to: 2,way: 1,surface: 3,name: "Beispiel",incline: 0)]
        var original = try LocalRouter.plan(graph: OfflineGraph(tiles: [tile], regional: true), document: document())
        original.coordinates = [point(5000),point(5900)]; original.surfaceSections = nil
        XCTAssertThrowsError(try LocalRouter.connect(graph: OfflineGraph(tiles: [tile]), original: original, waypoints: [], profile: RidingProfile(), position: point(20), heading: 90, traveled: 0, usedUnpaved: 0))
        let connection = try LocalRouter.connect(graph: OfflineGraph(tiles: [tile], regional: true), original: original, waypoints: [], profile: RidingProfile(), position: point(20), heading: 90, traveled: 0, usedUnpaved: 0)
        XCTAssertGreaterThan(connection.connector.distance, 5000)
    }
    func testPreferencesChooseDifferentLegalRoutesAndQualityStaysUnknown() throws {
        let id = OfflineTileID.at(point(0))
        var tile = tile(id: id)
        tile.nodes = [OfflineGraphNode(id: 1,coordinate: point(0)), OfflineGraphNode(id: 2,coordinate: point(100)),
                      OfflineGraphNode(id: 3,coordinate: point(500,300)), OfflineGraphNode(id: 4,coordinate: point(900)), OfflineGraphNode(id: 5,coordinate: point(1000))]
        let links: [(Int, Int, Bool)] = [(1,2,true),(2,4,false),(2,3,true),(3,4,true),(4,5,true)]
        tile.edges = links.map { a,b,cycle -> OfflineGraphEdge in
            OfflineGraphEdge(from: Int64(a),to: Int64(b),way: Int64(a*10+b),surface: cycle ? 3 : 5,name: "Beispiel",incline: 0,roadClass: cycle ? "cycleway" : "primary",cycleway: cycle,inclineKnown: true)
        }
        let graph = try OfflineGraph(tiles: [tile])
        var doc = document(); doc.profile.cyclePreference = .fast
        let fast = try LocalRouter.plan(graph: graph, document: doc)
        doc.profile.cyclePreference = .quiet
        let quiet = try LocalRouter.plan(graph: graph, document: doc)
        doc.profile.cyclePreference = .comfortable
        let comfortable = try LocalRouter.plan(graph: graph, document: doc)
        XCTAssertLessThan(fast.distance, quiet.distance)
        XCTAssertEqual(quiet.coordinates, comfortable.coordinates)
        XCTAssertTrue(quiet.cycleQuality?.allSatisfy { $0.cycleway == true } == true)
        var unknown = tile.edges[0]; unknown.roadClass = nil; unknown.cycleway = nil; unknown.inclineKnown = nil
        XCTAssertGreaterThan(CycleQuality.penalty(unknown, preference: .quiet), 0)
        tile.edges = [unknown]
        XCTAssertNil(CycleQuality.sections(route: fast, graph: try OfflineGraph(tiles: [tile])).last?.incline)
    }
    func testRegionalGridBenchmark() throws {
        let begin = ProcessInfo.processInfo.systemUptime
        let size = 100
        var nodes: [OfflineGraphNode] = [], edges: [OfflineGraphEdge] = []
        for y in 0..<size { for x in 0..<size {
            let id = Int64(y*size+x)
            nodes.append(OfflineGraphNode(id: id, coordinate: point(Double(x)*50,Double(y)*50)))
            for next in [x+1 < size ? id+1 : nil, y+1 < size ? id+Int64(size) : nil].compactMap({ $0 }) {
                let way = id*10000+next
                edges.append(OfflineGraphEdge(from: id,to: next,way: way,surface: 3,name: "Beispielnetz",incline: 0))
                edges.append(OfflineGraphEdge(from: next,to: id,way: way,surface: 3,name: "Beispielnetz",incline: 0))
            }
        }}
        let ids = Set(nodes.map { OfflineTileID.at($0.coordinate) }).sorted()
        var tiles = ids.map { id in OfflineGraphTile(version: 1,x: id.x,y: id.y,generatedAt: 1,compilerRevision: 3,nodes: [],edges: [],restrictions: []) }
        tiles[0].nodes = nodes; tiles[0].edges = edges
        let graph = try OfflineGraph(tiles: tiles, regional: true)
        var doc = TourDocument()
        doc.waypoints = [Waypoint(name: "Beispielstart",coordinate: nodes.first!.coordinate),Waypoint(name: "Beispielziel",coordinate: nodes.last!.coordinate)]
        let route = try LocalRouter.plan(graph: graph, document: doc)
        XCTAssertGreaterThan(route.distance, 9800)
        XCTAssertLessThan(route.distance, 10000)
        let elapsed = ProcessInfo.processInfo.systemUptime-begin
        print("REGION_BENCHMARK nodes=\(nodes.count) edges=\(edges.count) seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 30)
    }
    func testPublicTisnoReferenceAllPreferences() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("server/tests/fixtures/tisno_bridge_graph.json")
        let graph = try OfflineGraph(tiles: [JSONDecoder().decode(OfflineGraphTile.self, from: Data(contentsOf: url))])
        for preference in CyclePreference.allCases {
            var doc = TourDocument(); doc.profile.cyclePreference = preference
            doc.waypoints = [272268068,275001050].map { Waypoint(name: "Öffentliche Referenz Tisno", coordinate: graph.nodes[Int64($0)]!) }
            XCTAssertEqual(try LocalRouter.plan(graph: graph, document: doc).distance, 69.5, accuracy: 1)
        }
    }
}
