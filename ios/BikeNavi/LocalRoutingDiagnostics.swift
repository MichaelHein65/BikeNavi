#if DEBUG
import SwiftUI

/// Developer-only, deterministic on-device replay. This view does not construct
/// AppState, open a network client, start GPS, or modify the user's ride library.
struct LocalRoutingDiagnostics: View {
    @State private var status = "Lokale Routenprüfung läuft …"
    struct Position: Decodable { var latitude: Double; var longitude: Double; var heading: Double; var traveled: Double }
    var body: some View {
        Text(status).padding().task {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalRoutingCheck")
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let tile = try JSONDecoder().decode(OfflineGraphTile.self, from: Data(contentsOf: folder.appendingPathComponent("tile.json")))
                    let route = try JSONDecoder().decode(CalculatedRoute.self, from: Data(contentsOf: folder.appendingPathComponent("route.json")))
                    let positions = try JSONDecoder().decode([Position].self, from: Data(contentsOf: folder.appendingPathComponent("positions.json")))
                    let begin = ProcessInfo.processInfo.systemUptime
                    let graph = try OfflineGraph(tiles: [tile])
                    let indexSeconds = ProcessInfo.processInfo.systemUptime-begin
                    let waypoints = [Waypoint(name:"Teststart",coordinate:route.coordinates.first!),Waypoint(name:"Testziel",coordinate:route.coordinates.last!)]
                    var rows: [[String:Any]] = []
                    for p in positions {
                        let start = ProcessInfo.processInfo.systemUptime
                        do {
                            let connection = try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(),
                                position:Coordinate(latitude:p.latitude,longitude:p.longitude),heading:p.heading,traveled:p.traveled,usedUnpaved:0)
                            rows.append(["seconds":ProcessInfo.processInfo.systemUptime-start,"distance":connection.connector.distance,"join":connection.rejoinIndex,"ok":true])
                        } catch { rows.append(["ok":false,"error":error.localizedDescription]) }
                    }
                    let result: [String:Any] = ["nodes":graph.nodes.count,"edges":graph.edges.count,"indexSeconds":indexSeconds,"results":rows]
                    try JSONSerialization.data(withJSONObject: result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.deletingLastPathComponent().appendingPathComponent("LocalRoutingResult.json"),options:.atomic)
                    return "Lokale Prüfung abgeschlossen: \(rows.filter { $0["ok"] as? Bool == true }.count) von \(rows.count) Anschlüssen berechnet."
                }.value
                status = result
            } catch {
                status = error.localizedDescription
                try? Data(status.utf8).write(to:folder.deletingLastPathComponent().appendingPathComponent("LocalRoutingError.txt"),options:.atomic)
            }
        }
    }
}
#endif
