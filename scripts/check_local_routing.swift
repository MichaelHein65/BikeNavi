import Foundation

@main
struct CheckLocalRouting {
    static func main() async {
        do { try await run() } catch { print("Check failed: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--prepare" {
            let route = try JSONDecoder().decode(CalculatedRoute.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
            let env = ProcessInfo.processInfo.environment
            guard let url = env["BIKENAVI_SERVER_URL"].flatMap(URL.init(string:)), let token = env["BIKENAVI_TOKEN"] else { fatalError("Missing server configuration") }
            let store = OfflineRoutingStore(directory:URL(fileURLWithPath:CommandLine.arguments[3]))
            let graph = try await store.prepare(route:route,api:APIClient(baseURL:url,token:token)) { done,total in
                print("Preparation: \(done)/\(total)"); fflush(stdout)
            }
            print("Prepared complete corridor: \(graph.nodes.count) nodes, \(graph.edges.count) edges")
            return
        }
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: LocalRoutingCheck tile.json route.json") }
        let tile = try JSONDecoder().decode(OfflineGraphTile.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let route = try JSONDecoder().decode(CalculatedRoute.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let begin = ProcessInfo.processInfo.systemUptime
        let graph = try OfflineGraph(tiles:[tile])
        print("Graph: \(graph.nodes.count) nodes, \(graph.edges.count) edges, index \(String(format:"%.3f",ProcessInfo.processInfo.systemUptime-begin)) s")
        let waypoints = [Waypoint(name:"Start",coordinate:route.coordinates.first!),Waypoint(name:"Ziel",coordinate:route.coordinates.last!)]
        var attempts = 0, successes = 0, durations: [Double] = []
        var output: [[String:Any]] = []
        for edge in graph.edges {
            guard let position = graph.nodes[edge.from], let next = graph.nodes[edge.to], position.distance(to:next) > 15 else { continue }
            var tracker = RouteTracker()
            guard let progress = tracker.update(position:position,timestamp:1,route:route), (40...120).contains(progress.distanceFromRoute),
                  progress.traveled < (LocalRouteMetrics.distances(route).last ?? 0) - 200 else { continue }
            attempts += 1
            let start = ProcessInfo.processInfo.systemUptime
            do {
                let heading = LocalGeometry.bearing(position,next)
                let result = try LocalRouter.connect(graph:graph,original:route,waypoints:waypoints,profile:RidingProfile(),
                    position:position,heading:heading,traveled:progress.traveled,usedUnpaved:0)
                let duration = ProcessInfo.processInfo.systemUptime-start
                durations.append(duration); successes += 1
                output.append(["latitude":position.latitude,"longitude":position.longitude,"heading":heading,"traveled":progress.traveled])
                print("Connector \(successes): \(Int(result.connector.distance)) m, \(String(format:"%.4f",duration)) s, rejoin \(result.rejoinIndex)")
            } catch { if attempts <= 5 { print("Rejected: \(error.localizedDescription)") } }
            if successes == 10 || attempts == 50 { break }
        }
        guard successes >= 3 else { fatalError("Not enough real connections: \(successes)/\(attempts)") }
        let file = URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("positions.json")
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:file,options:.atomic)
        print("Successes: \(successes)/\(attempts), max \(String(format:"%.4f",durations.max()!)) s; positions saved for device replay")
    }
}
