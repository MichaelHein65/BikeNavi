#if DEBUG
import Foundation

extension AppState {
    func prepareRegionalPreview() async {
        do {
            serverURL = ""; token = ""; voice = false
            chooseApplication(.cycling)
            let origin = Coordinate(latitude: 49.4146, longitude: 8.6815, altitude: 110)
            let points = (0...4).map { i in Coordinate(latitude: origin.latitude + (i % 2 == 0 ? 0 : 0.001), longitude: origin.longitude+Double(i)*0.002, altitude: 110+Double(i)*3) }
            let id = OfflineTileID.at(origin)
            var tile = OfflineGraphTile(version: 1, x: id.x, y: id.y, generatedAt: 1792533600, compilerRevision: 3,
                nodes: points.enumerated().map { OfflineGraphNode(id: Int64($0.offset), coordinate: $0.element) },
                edges: [], restrictions: [])
            for i in 0..<4 {
                tile.edges.append(OfflineGraphEdge(from: Int64(i), to: Int64(i+1), way: Int64(i), surface: 3, name: "Beispielweg", incline: 2, roadClass: "cycleway", cycleway: true, inclineKnown: true))
                tile.edges.append(OfflineGraphEdge(from: Int64(i+1), to: Int64(i), way: Int64(i), surface: 3, name: "Beispielweg", incline: -2, roadClass: "cycleway", cycleway: true, inclineKnown: true))
            }
            tile.nodes += [OfflineGraphNode(id: 8, coordinate: Coordinate(latitude: origin.latitude+0.003,longitude: origin.longitude+0.002)),
                           OfflineGraphNode(id: 9, coordinate: Coordinate(latitude: origin.latitude+0.003,longitude: origin.longitude+0.006))]
            for (a,b) in [(1,8),(8,9),(9,3)] {
                tile.edges.append(OfflineGraphEdge(from: Int64(a),to: Int64(b),way: Int64(a*10+b),surface: 3,name: "Beispiel-Nebenweg",incline: 0))
            }
            tile.pois = [OfflinePOI(id: "example/water", name: "Beispieldaten · Trinkbrunnen", category: .water, coordinate: points[1], source: "Synthetische Beispieldaten", openingHours: nil),
                         OfflinePOI(id: "example/rest", name: "Beispieldaten · Rastplatz", category: .rest, coordinate: points[2], source: "Synthetische Beispieldaten", openingHours: nil)]
            let data = try JSONEncoder().encode(tile)
            let package = RegionTilePackage(schema: 1, bytes: data.count, sha256: RegionTilePackage.hash(data), data: data)
            let region = try await OfflineRegionStore.shared.download(name: "Beispieldaten · Heidelberg", tiles: [id], refresh: true,
                fetch: { _, _ in package }, progress: { _, _ in })
            var example = TourDocument()
            example.title = "Beispieldaten · Offline-Radtour"
            example.waypoints = [Waypoint(name: "Beispielstart", coordinate: points[0]), Waypoint(name: "Beispielziel", coordinate: points[4])]
            example.profile.cyclePreference = .comfortable
            example.route = try LocalRouter.plan(graph: OfflineGraph(tiles: [tile], regional: true), document: example)
            plan = example
            var ride = example; ride.id = UUID(); ride.sourcePlanID = example.id; ride.kind = .ride; ride.recordingState = .paused
            activeRide = ride
            try await useRegion(region)
            UserDefaults.standard.set("navigation", forKey: "ridePresentation")
            restoreLocalRouting(); tab = 1
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
