import XCTest
@testable import BikeNaviCore

final class LocalRoutingTests: XCTestCase {
    func point(_ x: Double, _ y: Double = 0) -> Coordinate {
        Coordinate(latitude: 49 + y/111_320, longitude: 8 + x/(111_320*cos(49 * .pi/180)))
    }
    func fixture(surface: Int = 3, rule: Bool = false) throws -> (OfflineGraphTile, CalculatedRoute, [Waypoint]) {
        var nodes = (0...8).map { OfflineGraphNode(id: Int64($0), coordinate: point(Double($0)*100)) }
        nodes += [OfflineGraphNode(id: 20, coordinate: point(100,50)), OfflineGraphNode(id: 21, coordinate: point(200,50))]
        var edges: [OfflineGraphEdge] = []
        func add(_ a: Int64, _ b: Int64, _ way: Int64, _ s: Int = 3) {
            edges += [OfflineGraphEdge(from: a, to: b, way: way, surface: s, name: "Testweg", incline: 0),
                      OfflineGraphEdge(from: b, to: a, way: way, surface: s, name: "Testweg", incline: 0)]
        }
        for i in 0..<8 { add(Int64(i),Int64(i+1),100) }
        add(20,21,200); add(21,2,300,surface)
        let id = OfflineTileID.at(point(100,50))
        let rules = rule ? [OfflineTurnRule(via: 2, fromWay: 300, toWays: [100], only: false, uTurn: false)] : []
        let tile = OfflineGraphTile(version: 1, x: id.x, y: id.y, generatedAt: 1, nodes: nodes, edges: edges, restrictions: rules)
        let route = CalculatedRoute(id: UUID(), coordinates: (0...8).map { point(Double($0)*100) }, distance: 800, duration: 180, ascent: 0, descent: 0,
            maneuvers: [Maneuver(instruction: "Ziel", distance: 0, coordinateIndex: 8, type: 10)], surfaces: [], warnings: [], provider: "test", calculatedAt: 1,
            surfaceSections: [RouteSurfaceSection(startIndex: 0, endIndex: 8, surface: 3)])
        return (tile,route,[Waypoint(name: "Start", coordinate: point(0)), Waypoint(name: "Ziel", coordinate: point(800))])
    }
    func connect(surface: Int = 3, used: Double = 0, preference: SurfacePreference = .any, rule: Bool = false) throws -> LocalConnection {
        let (tile,route,waypoints) = try fixture(surface: surface, rule: rule)
        return try LocalRouter.connect(graph: OfflineGraph(tiles: [tile]), original: route, waypoints: waypoints,
            profile: RidingProfile(surface: preference), position: point(150,50), heading: 90, traveled: 0, usedUnpaved: used)
    }
    func testLocalConnectorRetainsOriginalRouteAndRemainingGeometry() throws {
        let (_,original,_) = try fixture()
        let result = try connect()
        XCTAssertEqual(result.rejoinIndex,2)
        XCTAssertLessThan(result.connector.distance, 110)
        XCTAssertEqual(result.connector.coordinates.last, original.coordinates[2])
        XCTAssertEqual(result.unpavedDistance,0,accuracy: 0.5)
        let combined = LocalRouteMetrics.combined(original: original, state: LocalNavigationState(connector: result.connector, rejoinIndex: result.rejoinIndex))
        XCTAssertEqual(Array(combined.coordinates.suffix(7)),Array(original.coordinates.suffix(7)))
        XCTAssertEqual(combined.maneuvers.last?.type,10)
        XCTAssertEqual(combined.maneuvers.last?.coordinateIndex,combined.coordinates.count-1)
        XCTAssertEqual(original.coordinates.first,point(0))
    }
    func testJoinInstructionUsesTheNewApproachRatherThanOldTurn() throws {
        var (_,original,_) = try fixture()
        original.maneuvers.insert(Maneuver(instruction:"Rechts aus alter Richtung",distance:0,coordinateIndex:2,type:1),at:0)
        let connection = try connect()
        let combined = LocalRouteMetrics.combined(original:original,state:LocalNavigationState(connector:connection.connector,rejoinIndex:2))
        let join = combined.maneuvers.filter { $0.coordinateIndex == connection.connector.coordinates.count-1 }
        XCTAssertEqual(join.count,1)
        XCTAssertEqual(join.first?.type,0) // Approach from the north, then turn east: left.
        XCTAssertFalse(combined.maneuvers.contains(where:{$0.instruction == "Rechts aus alter Richtung"}))
    }

    func testTurnRestrictionCannotBeBypassedBySearch() {
        XCTAssertThrowsError(try connect(rule: true))
    }
    func testOneHundredMetreBudgetIncludesEarlierConnectorsAndUnknownSurfaces() throws {
        let result = try connect(surface: 0, used: 49, preference: .pavedOnly)
        XCTAssertGreaterThan(result.unpavedDistance,49)
        XCTAssertLessThan(result.unpavedDistance,51)
        XCTAssertThrowsError(try connect(surface: 0, used: 51, preference: .pavedOnly))
        XCTAssertNoThrow(try connect(surface: 10, used: 500, preference: .any))
    }
    func testSurfaceBudgetIncludesAccessFromActualGPSPosition() throws {
        let (tile,route,waypoints) = try fixture(surface:0)
        let graph = try OfflineGraph(tiles:[tile])
        let result = try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(surface:.pavedOnly),position:point(150,60),heading:90,traveled:0,usedUnpaved:35)
        XCTAssertEqual(result.unpavedDistance,60,accuracy:1)
        XCTAssertThrowsError(try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(surface:.pavedOnly),position:point(150,60),heading:90,traveled:0,usedUnpaved:45))
    }

    func testRemainingOriginalGravelCountsAgainstSameBudget() throws {
        var (tile,original,waypoints) = try fixture(surface: 0)
        for i in tile.edges.indices where Set([tile.edges[i].from,tile.edges[i].to]) == Set<Int64>([7,8]) { tile.edges[i].surface = 10 }
        var route = original
        route.surfaceSections = [RouteSurfaceSection(startIndex: 0, endIndex: 7, surface: 3),RouteSurfaceSection(startIndex: 7,endIndex: 8,surface: 10)]
        XCTAssertThrowsError(try LocalRouter.connect(graph: OfflineGraph(tiles:[tile]),original:route,waypoints:waypoints,
            profile:RidingProfile(surface:.pavedOnly),position:point(150,50),heading:90,traveled:0,usedUnpaved:0))
    }
    func testMandatoryWaypointAndReturnLegAreNotSkipped() throws {
        let (tile,original,_) = try fixture()
        var route = original
        route.coordinates += original.coordinates.dropLast().reversed()
        route.surfaceSections = [RouteSurfaceSection(startIndex:0,endIndex:route.coordinates.count-1,surface:3)]
        let waypoints = [Waypoint(name:"Start",coordinate:point(0)),Waypoint(name:"Pflichtstopp",coordinate:point(400)),Waypoint(name:"Ziel",coordinate:point(0))]
        let result = try LocalRouter.connect(graph: OfflineGraph(tiles:[tile]),original:route,waypoints:waypoints,
            profile:RidingProfile(),position:point(150,50),heading:90,traveled:0,usedUnpaved:0)
        XCTAssertLessThanOrEqual(result.rejoinIndex,4)
    }
    func testMovementAlongConnectorIsTrimmedButDifferentRoadIsRejected() throws {
        let connector = try connect().connector
        let trimmed = try XCTUnwrap(LocalRouteMetrics.trim(connector,to:point(180,50),heading:90))
        XCTAssertLessThan(trimmed.distance,connector.distance)
        XCTAssertNil(LocalRouteMetrics.trim(connector,to:point(180,200),heading:90))
        XCTAssertNil(LocalRouteMetrics.trim(connector,to:point(180,50),heading:270))
    }
    func testSearchBudgetAndMissingCoverageAreExplicitErrors() throws {
        let (tile,route,waypoints) = try fixture()
        let graph = try OfflineGraph(tiles:[tile])
        XCTAssertThrowsError(try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(),position:point(150,50),heading:90,traveled:0,usedUnpaved:0,timeLimit:0))
        XCTAssertThrowsError(try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(),position:point(100_000),heading:90,traveled:0,usedUnpaved:0))
    }
    func testCacheSurvivesReopenWithoutAnyServerClient() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let (base,route,_) = try fixture()
        for id in try OfflineTileID.corridor(route.coordinates) {
            var tile = base; tile.x=id.x; tile.y=id.y
            try JSONEncoder().encode(tile).write(to:directory.appendingPathComponent(id.key+".json"),options:.atomic)
        }
        let store = OfflineRoutingStore(directory:directory)
        let graph = try await store.prepare(route:route,api:nil) { _,_ in }
        XCTAssertFalse(graph.edges.isEmpty)
        do {
            _ = try await store.prepare(route: route, api: nil, refresh: true) { _,_ in }
            XCTFail("Refresh without a connection must fail without replacing the old manifest")
        } catch { }
        let reopened = OfflineRoutingStore(directory:directory)
        let loaded = try await reopened.load(route:route)
        XCTAssertEqual(loaded.edges.count,graph.edges.count)
    }
    func testInaccurateOrRepeatedGPSSamplesDoNotTriggerRerouting() {
        var policy = ReroutePolicy()
        for t in [100.0,103,106] { XCTAssertFalse(policy.observe(distanceFromRoute:80,timestamp:t,accuracy:40)) }
        XCTAssertFalse(policy.observe(distanceFromRoute:80,timestamp:110))
        XCTAssertFalse(policy.observe(distanceFromRoute:80,timestamp:110))
        XCTAssertFalse(policy.observe(distanceFromRoute:80,timestamp:116))
        XCTAssertTrue(policy.observe(distanceFromRoute:80,timestamp:118))
    }
    func testLongTourSearchOnlyBuildsAShortConnector() throws {
        let (tile,base,_) = try fixture()
        var route = base
        route.coordinates = (0...10_000).map { point(Double($0)*20) }
        route.surfaceSections = [RouteSurfaceSection(startIndex: 0, endIndex: 10_000, surface: 3)]
        let begin = ProcessInfo.processInfo.systemUptime
        let result = try LocalRouter.connect(graph: OfflineGraph(tiles:[tile]), original:route,
            waypoints:[Waypoint(name:"Start",coordinate:route.coordinates.first!),Waypoint(name:"Ziel",coordinate:route.coordinates.last!)],
            profile:RidingProfile(),position:point(150,50),heading:90,traveled:0,usedUnpaved:0)
        XCTAssertLessThan(result.connector.distance,300)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-begin,2)
    }

    func testRejoinMinimizesWholeRemainingTripInsteadOfShortestConnector() throws {
        let coords = [point(0), point(200), point(200,1000), point(800,1000), point(800), point(1000)]
        var nodes = coords.enumerated().map { OfflineGraphNode(id: Int64($0.offset), coordinate: $0.element) }
        nodes += [OfflineGraphNode(id: 10, coordinate: point(0,-100)), OfflineGraphNode(id: 11, coordinate: point(200,-100)), OfflineGraphNode(id: 12, coordinate: point(800,-100))]
        var edges: [OfflineGraphEdge] = []
        func edge(_ a: Int64, _ b: Int64, _ way: Int64) {
            edges.append(OfflineGraphEdge(from:a,to:b,way:way,surface:3,name:"Weg",incline:0))
        }
        for i in 0..<5 { edge(Int64(i),Int64(i+1),100) }
        edge(10,11,200); edge(11,12,200); edge(11,1,300); edge(12,4,400)
        let id = OfflineTileID.at(point(100,-100))
        let graph = try OfflineGraph(tiles:[OfflineGraphTile(version:1,x:id.x,y:id.y,generatedAt:1,nodes:nodes,edges:edges,restrictions:[])])
        let original = CalculatedRoute(id:UUID(),coordinates:coords,distance:3000,duration:600,ascent:0,descent:0,maneuvers:[],surfaces:[],warnings:[],provider:"test",calculatedAt:1,
            surfaceSections:[RouteSurfaceSection(startIndex:0,endIndex:5,surface:3)])
        let waypoints = [Waypoint(name:"Start",coordinate:coords[0]),Waypoint(name:"Ziel",coordinate:coords[5])]
        let result = try LocalRouter.connect(graph:graph,original:original,waypoints:waypoints,profile:RidingProfile(surface:.any),position:point(100,-100),heading:90,traveled:0,usedUnpaved:0)
        XCTAssertEqual(result.rejoinIndex,4)
        XCTAssertLessThan(result.connector.distance + LocalRouteMetrics.distances(original).last! - LocalRouteMetrics.distances(original)[result.rejoinIndex],1100)
        var mandatory = waypoints
        mandatory.insert(Waypoint(name:"Pflichtstopp",coordinate:coords[2]),at:1)
        let constrained = try LocalRouter.connect(graph:graph,original:original,waypoints:mandatory,profile:RidingProfile(surface:.any),position:point(100,-100),heading:90,traveled:0,usedUnpaved:0)
        XCTAssertLessThanOrEqual(constrained.rejoinIndex,2)
    }

    func testPhonePlansCompleteRouteAndKeepsIntermediateStop() throws {
        let (tile,_,waypoints) = try fixture()
        var document = TourDocument()
        document.waypoints = [waypoints[0],Waypoint(name:"Stopp",coordinate:point(400)),waypoints[1]]
        let route = try LocalRouter.plan(graph:OfflineGraph(tiles:[tile]),document:document)
        XCTAssertEqual(route.coordinates.first,point(0))
        XCTAssertEqual(route.coordinates.last,point(800))
        let indices = try XCTUnwrap(route.waypointIndices)
        XCTAssertEqual(indices.count,3)
        XCTAssertEqual(route.coordinates[indices[1]],point(400))
        XCTAssertEqual(route.maneuvers.last?.type,10)
        XCTAssertEqual(route.distance,800,accuracy:2)
    }

    func testPlanningUsesCachedGraphWithNoPiAndPersistsNavigationPackage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let (base,route,waypoints) = try fixture()
        for id in try OfflineTileID.corridor(route.coordinates) {
            var tile = base; tile.x = id.x; tile.y = id.y
            try JSONEncoder().encode(tile).write(to:directory.appendingPathComponent(id.key+".json"))
        }
        var document = TourDocument(); document.waypoints = waypoints
        let store = OfflineRoutingStore(directory:directory)
        let (planned,_) = try await store.plan(document:document,api:nil) { _,_ in }
        let reopened = OfflineRoutingStore(directory:directory)
        let loaded = try await reopened.load(route:planned)
        XCTAssertFalse(loaded.edges.isEmpty)
    }

    func testPlanningExpandsCorridorForDetourAndPersistsExpandedMap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let coords = [(43.775, 15.775), (43.795, 15.775), (43.825, 15.775),
                      (43.825, 15.925), (43.795, 15.925), (43.775, 15.925)].map {
            Coordinate(latitude: $0.0, longitude: $0.1)
        }
        let nodes = coords.enumerated().map { OfflineGraphNode(id: Int64($0.offset), coordinate: $0.element) }
        let edges = (0..<5).map {
            OfflineGraphEdge(from: Int64($0), to: Int64($0 + 1), way: Int64($0),
                             surface: 3, name: "Umweg", incline: 0)
        }
        let initial = try OfflineTileID.corridor([coords[0], coords[5]])
        let expanded = try OfflineTileID.expanded(initial)
        let bridgeTile = OfflineTileID.at(coords[2])
        XCTAssertFalse(initial.contains(bridgeTile))
        XCTAssertTrue(expanded.contains(bridgeTile))
        // Only the northern side is cached. Missing southern data must not
        // prevent a successful offline search on the other side.
        let cached = try OfflineTileID.extended(initial, dx: 0, dy: 1)
        for id in cached {
            let tile = OfflineGraphTile(version: 1, x: id.x, y: id.y, generatedAt: 1, nodes: nodes,
                edges: id == bridgeTile ? Array(edges[1...3]) : [edges[0], edges[4]], restrictions: [])
            try JSONEncoder().encode(tile).write(to: directory.appendingPathComponent(id.key + ".json"))
        }
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Start", coordinate: coords[0]), Waypoint(name: "Ziel", coordinate: coords[5])]
        let store = OfflineRoutingStore(directory: directory)
        let (route, graph) = try await store.plan(document: document, api: nil) { _, _ in }
        XCTAssertTrue(graph.tiles.isSubset(of: Set(expanded)))
        XCTAssertTrue(graph.tiles.contains(bridgeTile))
        XCTAssertLessThan(graph.tiles.count, expanded.count)
        XCTAssertTrue(route.coordinates.contains(coords[2]))
        XCTAssertTrue(route.coordinates.contains(coords[3]))
        XCTAssertEqual(route.coordinates.last, coords[5])
        let reopened = OfflineRoutingStore(directory: directory)
        let restored = try await reopened.load(route: route)
        XCTAssertEqual(restored.tiles, graph.tiles)
        // A subsequent offline calculation can reuse the expanded graph.
        let (again, _) = try await store.plan(document: document, api: nil) { _, _ in }
        XCTAssertEqual(again.coordinates, route.coordinates)
    }

    func testCorridorExpansionIsBoundedAndClampedToValidTiles() throws {
        let corner = try OfflineTileID.expanded([OfflineTileID(x: 0, y: 0)])
        XCTAssertEqual(corner.count, 4)
        XCTAssertTrue(corner.allSatisfy { $0.x >= 0 && $0.y >= 0 })
        let large = (0..<120).map { OfflineTileID(x: 3000 + $0, y: 2000) }
        XCTAssertThrowsError(try OfflineTileID.expanded(large)) { error in
            guard case LocalRoutingError.tooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testLocalPlanningPreservesSurfaceColorsWithAccessSegmentAndMultipleLegs() throws {
        var (tile,_,_) = try fixture()
        for i in tile.edges.indices where tile.edges[i].from >= 4 && tile.edges[i].to >= 4 && tile.edges[i].way == 100 {
            tile.edges[i].surface = 10
        }
        let graph = try OfflineGraph(tiles:[tile])
        for stops in [[point(0,10),point(800)], [point(0),point(400),point(800)], [point(0,10),point(300),point(500),point(800)]] {
            var document = TourDocument()
            document.profile.surface = .any
            document.waypoints = stops.enumerated().map { Waypoint(name:"Stopp \($0.offset)",coordinate:$0.element) }
            let route = try LocalRouter.plan(graph:graph,document:document)
            XCTAssertEqual(route.surfaceSections,route.coloredSections)
            XCTAssertTrue(route.coloredSections.contains { $0.surface == 3 })
            XCTAssertTrue(route.coloredSections.contains { $0.surface == 10 })
            XCTAssertEqual(route.coloredSections.last?.endIndex,route.coordinates.count-1)
            XCTAssertLessThan(LocalRouteMetrics.unpaved(route),420)
            let saved = try JSONDecoder().decode(CalculatedRoute.self,from:JSONEncoder().encode(route))
            XCTAssertEqual(saved.coloredSections,route.coloredSections)
        }
    }

    func testSavedLocalSurfaceRepairKeepsGeometryAndRestoresKnownColors() throws {
        var (tile,route,_) = try fixture()
        for i in tile.edges.indices where tile.edges[i].way == 100 && tile.edges[i].from >= 4 && tile.edges[i].to >= 4 { tile.edges[i].surface = 10 }
        route.provider = "BikeNavi iPhone · OpenStreetMap"
        route.surfaceSections = [RouteSurfaceSection(startIndex:0,endIndex:4,surface:3),
            RouteSurfaceSection(startIndex:4,endIndex:8,surface:0),RouteSurfaceSection(startIndex:4,endIndex:8,surface:10)]
        XCTAssertTrue(route.needsLocalSurfaceRepair)
        let graph = try OfflineGraph(tiles:[tile])
        let fixed = route.repairingLocalSurfaces(graph:graph)
        XCTAssertFalse(fixed.needsLocalSurfaceRepair)
        XCTAssertEqual(fixed.id,route.id)
        XCTAssertEqual(fixed.coordinates,route.coordinates)
        XCTAssertEqual(fixed.maneuvers,route.maneuvers)
        XCTAssertEqual(fixed.coloredSections.map(\.surface),[3,3,3,3,10,10,10,10])
        XCTAssertEqual(fixed.surfaces.count,2)
        XCTAssertEqual(fixed.repairingLocalSurfaces(graph:graph),fixed)
        // A genuinely unknown surface must remain unknown.
        var unknown = route
        unknown.surfaceSections = [RouteSurfaceSection(startIndex:0,endIndex:8,surface:0)]
        XCTAssertFalse(unknown.needsLocalSurfaceRepair)
        XCTAssertEqual(unknown.repairingLocalSurfaces(graph:graph),unknown)
    }

    func testUnmatchedPlanningPointNamesThePointInsteadOfWaitingForGPS() throws {
        let (tile, _, _) = try fixture()
        let graph = try OfflineGraph(tiles: [tile])
        for startMissing in [true, false] {
            var document = TourDocument()
            let name = startMissing ? "Entfernter Start" : "Entferntes Ziel"
            document.waypoints = [Waypoint(name: startMissing ? name : "Start", coordinate: point(0, startMissing ? 400 : 0)),
                                  Waypoint(name: startMissing ? "Ziel" : name, coordinate: point(800, startMissing ? 0 : -400))]
            XCTAssertThrowsError(try LocalRouter.plan(graph: graph, document: document)) { error in
                guard case LocalRoutingError.waypointOffNetwork(let pointName) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(pointName, name)
                XCTAssertFalse(error.localizedDescription.contains("Position"))
            }
        }
    }

    func testMatchingCoversRequestedRadiusAcrossNarrowLongitudeBins() throws {
        let origin = Coordinate(latitude: 74.0005, longitude: 8)
        let nodes = [OfflineGraphNode(id: 1, coordinate: Coordinate(latitude: 74, longitude: 8.008)),
                     OfflineGraphNode(id: 2, coordinate: Coordinate(latitude: 74.001, longitude: 8.008))]
        let edge = OfflineGraphEdge(from: 1, to: 2, way: 1, surface: 3, name: "Straße", incline: 0)
        let id = OfflineTileID.at(origin)
        let graph = try OfflineGraph(tiles: [OfflineGraphTile(version: 1, x: id.x, y: id.y,
            generatedAt: 1, nodes: nodes, edges: [edge], restrictions: [])])
        let match = try XCTUnwrap(graph.matches(origin, maxDistance: 250).first)
        XCTAssertGreaterThan(match.distance, 240)
        XCTAssertLessThan(match.distance, 250)
        XCTAssertTrue(graph.matches(origin, maxDistance: 25).isEmpty)
    }

    func testPlanningPOIOffRoadKeepsAccessExplicitWithoutChangingNavigationMatching() throws {
        let (tile, _, _) = try fixture()
        let graph = try OfflineGraph(tiles: [tile])
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Brunnen", coordinate: point(0, 110)),
                              Waypoint(name: "Strand", coordinate: point(800, -120))]
        let route = try LocalRouter.plan(graph: graph, document: document)
        XCTAssertEqual(route.coordinates.first, document.waypoints.first?.coordinate)
        XCTAssertEqual(route.coordinates.last, document.waypoints.last?.coordinate)
        XCTAssertEqual(route.coloredSections.first?.surface, 0)
        XCTAssertEqual(route.coloredSections.last?.surface, 0)
        XCTAssertTrue(route.warnings.contains { $0.contains("Brunnen") && $0.contains("Zugang") })
        XCTAssertTrue(route.warnings.contains { $0.contains("Strand") && $0.contains("Zugang") })
        XCTAssertTrue(route.maneuvers.first?.instruction.contains("Zugang") == true)
        document.profile.surface = .pavedOnly
        XCTAssertThrowsError(try LocalRouter.plan(graph: graph, document: document))
        // The more permissive POI snap must never affect live GPS matching.
        XCTAssertThrowsError(try LocalRouter.connect(graph: graph, original: route, waypoints: document.waypoints,
            profile: RidingProfile(), position: point(0, 110), heading: nil, traveled: 0, usedUnpaved: 0))
    }

    func testPlanningAtJunctionDoesNotWaitForNavigationHeading() throws {
        var (tile,_,waypoints) = try fixture()
        // A second mapped way shares the start point. Planning may select either
        // legal start; live navigation still requires an unambiguous road match.
        tile.nodes += [OfflineGraphNode(id:30,coordinate:point(-100)),OfflineGraphNode(id:31,coordinate:point(100))]
        tile.edges.append(OfflineGraphEdge(from:30,to:31,way:999,surface:3,name:"Nebenweg",incline:0))
        var document = TourDocument(); document.waypoints = waypoints
        XCTAssertNoThrow(try LocalRouter.plan(graph:OfflineGraph(tiles:[tile]),document:document))
    }

    func testSurfaceBudgetKeepsLongerPavedAlternativeAtSharedJunction() throws {
        let coordinates = [point(0), point(40, 60), point(80), point(90), point(130)]
        let nodes = coordinates.enumerated().map { OfflineGraphNode(id: Int64($0.offset), coordinate: $0.element) }
        let links: [(Int, Int, Int)] = [(0, 2, 10), (0, 1, 3), (1, 2, 3), (2, 3, 3), (3, 4, 10)]
        let edges: [OfflineGraphEdge] = links.map { a, b, surface in
            OfflineGraphEdge(from: Int64(a), to: Int64(b), way: Int64(a * 10 + b),
                surface: surface, name: "Testweg", incline: 0)
        }
        let id = OfflineTileID.at(point(0))
        let graph = try OfflineGraph(tiles: [OfflineGraphTile(version: 1, x: id.x, y: id.y,
            generatedAt: 1, nodes: nodes, edges: edges, restrictions: [])])
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Start", coordinate: coordinates[0]),
                              Waypoint(name: "Ziel", coordinate: coordinates[4])]
        for preference in [SurfacePreference.any, .preferPaved, .pavedOnly] {
            document.profile.surface = preference
            let route = try LocalRouter.plan(graph: graph, document: document)
            XCTAssertEqual(LocalRouteMetrics.unpaved(route), preference == .any ? 120 : 40, accuracy: 1)
            XCTAssertEqual(route.coordinates.contains(coordinates[1]), preference != .any)
        }
    }

    func testGravelAllowedDoesNotEnumerateEverySurfaceCombinationBeforeADetour() throws {
        // Successive paved detours and shorter gravel alternatives create many
        // cost/surface tradeoffs. With gravel allowed only route cost matters.
        var nodes = [OfflineGraphNode(id: 0, coordinate: point(0))]
        var edges: [OfflineGraphEdge] = []
        func add(_ a: Int64, _ b: Int64, surface: Int) {
            edges.append(OfflineGraphEdge(from: a, to: b, way: a * 1000 + b,
                surface: surface, name: "Testweg", incline: 0))
        }
        var x = 0.0
        var current: Int64 = 0
        for i in 0..<20 {
            let width = 20 + Double((i * 7919) % 101) / 10
            let middle = current + 1, end = current + 2, merge = current + 3
            nodes += [OfflineGraphNode(id: middle, coordinate: point(x + width / 2, width / 3)),
                      OfflineGraphNode(id: end, coordinate: point(x + width)),
                      OfflineGraphNode(id: merge, coordinate: point(x + width + 5))]
            add(current, end, surface: 10)
            add(current, middle, surface: 3)
            add(middle, end, surface: 3)
            add(end, merge, surface: 3)
            x += width + 5
            current = merge
        }
        // The destination is reached around an obstacle, not in a straight line.
        nodes += [OfflineGraphNode(id: 100, coordinate: point(x, 2000)),
                  OfflineGraphNode(id: 101, coordinate: point(-500, 2000))]
        add(current, 100, surface: 3)
        add(100, 101, surface: 3)
        let id = OfflineTileID.at(point(0))
        let graph = try OfflineGraph(tiles: [OfflineGraphTile(version: 1, x: id.x, y: id.y,
            generatedAt: 1, nodes: nodes, edges: edges, restrictions: [])])
        var document = TourDocument()
        document.waypoints = [Waypoint(name: "Start", coordinate: point(0)),
                              Waypoint(name: "Ziel", coordinate: point(-500, 2000))]
        let route = try LocalRouter.plan(graph: graph, document: document)
        XCTAssertEqual(route.distance, x + 2000 + x + 500, accuracy: 15)
        XCTAssertGreaterThan(LocalRouteMetrics.unpaved(route), 400)
        XCTAssertEqual(route.coordinates.last, document.waypoints.last?.coordinate)
    }

    func testPlanningHandlesLongLegAndHonorsOneWay() throws {
        let nodes = (0...80).map { OfflineGraphNode(id:Int64($0),coordinate:point(Double($0)*100)) }
        let edges = (0..<80).map { OfflineGraphEdge(from:Int64($0),to:Int64($0+1),way:1,surface:3,name:"Einbahnweg",incline:0) }
        let id = OfflineTileID.at(point(0))
        let graph = try OfflineGraph(tiles:[OfflineGraphTile(version:1,x:id.x,y:id.y,generatedAt:1,nodes:nodes,edges:edges,restrictions:[])])
        var document = TourDocument()
        document.waypoints = [Waypoint(name:"Start",coordinate:point(0)),Waypoint(name:"Ziel",coordinate:point(8000))]
        let route = try LocalRouter.plan(graph:graph,document:document)
        XCTAssertEqual(route.distance,8000,accuracy:15)
        document.waypoints = [Waypoint(name:"Start",coordinate:point(800)),Waypoint(name:"Ziel",coordinate:point(0))]
        XCTAssertThrowsError(try LocalRouter.plan(graph:graph,document:document))
    }

    func testMagnetAdvancesAlongRouteButReleasesForRealDeviationOrWrongHeading() throws {
        let (_,route,_) = try fixture()
        var tracker = RouteTracker()
        let first = try XCTUnwrap(tracker.update(position:point(100,15),timestamp:100,route:route,heading:90))
        XCTAssertLessThan(try XCTUnwrap(first.snappedPosition).distance(to:point(100)),1)
        let second = try XCTUnwrap(tracker.update(position:point(130,20),timestamp:103,route:route,heading:90))
        XCTAssertGreaterThan(second.traveled,first.traveled)
        let off = try XCTUnwrap(tracker.update(position:point(160,45),timestamp:106,route:route,heading:90))
        XCTAssertNil(off.snappedPosition)
        XCTAssertEqual(off.traveled,second.traveled)
        XCTAssertNil(tracker.update(position:point(130,15),timestamp:109,route:route,heading:270)?.snappedPosition)
        XCTAssertNil(tracker.update(position:point(130,15),timestamp:112,route:route,heading:90,accuracy:50)?.snappedPosition)
    }

    func testConflictingTileAccessNeverReopensBlockedWay() throws {
        let (a,_,_) = try fixture()
        var b = a; b.excludedWays = [300]
        let graph = try OfflineGraph(tiles:[a,b])
        XCTAssertFalse(graph.edges.contains(where:{$0.way == 300}))
    }
}
