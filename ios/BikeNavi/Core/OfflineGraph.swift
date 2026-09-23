import Foundation

struct OfflineTileID: Codable, Hashable, Comparable {
    var x: Int
    var y: Int
    static func < (a: Self, b: Self) -> Bool { a.y == b.y ? a.x < b.x : a.y < b.y }
    var key: String { "1-\(x)-\(y)" }
    static func at(_ point: Coordinate) -> Self {
        Self(x: min(7199, max(0, Int(floor((point.longitude + 180) / 0.05)))),
             y: min(3599, max(0, Int(floor((point.latitude + 90) / 0.05)))))
    }
    /// Add one ring of surrounding tiles for detours around rivers or other gaps.
    static func expanded(_ ids: [Self]) throws -> [Self] {
        var result = Set(ids)
        for id in ids {
            for x in max(0, id.x - 1)...min(7199, id.x + 1) {
                for y in max(0, id.y - 1)...min(3599, id.y + 1) {
                    result.insert(Self(x: x, y: y))
                    guard result.count <= 120 else { throw LocalRoutingError.tooLarge }
                }
            }
        }
        return result.sorted()
    }
    /// A one-sided strip adds room for detours without loading a full city ring.
    static func extended(_ ids: [Self], dx: Int, dy: Int) throws -> [Self] {
        let shifted = ids.map { Self(x: min(7199, max(0, $0.x + dx)), y: min(3599, max(0, $0.y + dy))) }
        let result = Set(ids + shifted)
        guard result.count <= 120 else { throw LocalRoutingError.tooLarge }
        return result.sorted()
    }
    static func corridor(_ coordinates: [Coordinate]) throws -> [Self] {
        guard coordinates.count > 1 else { throw LocalRoutingError.noData }
        var result: Set<Self> = []
        func add(_ p: Coordinate) throws {
            guard abs(p.latitude) < 75, p.longitude.isFinite, p.latitude.isFinite else { throw LocalRoutingError.tooLarge }
            let dy = 2_000.0 / 111_000
            let dx = dy / cos(p.latitude * .pi / 180)
            let lo = at(Coordinate(latitude: p.latitude - dy, longitude: p.longitude - dx))
            let hi = at(Coordinate(latitude: p.latitude + dy, longitude: p.longitude + dx))
            for y in lo.y...hi.y { for x in lo.x...hi.x { result.insert(Self(x: x, y: y)) } }
            if result.count > 120 { throw LocalRoutingError.tooLarge }
        }
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let distance = a.distance(to: b)
            guard distance.isFinite, distance < 200_000, abs(a.longitude - b.longitude) < 180 else { throw LocalRoutingError.tooLarge }
            let steps = max(1, Int(ceil(distance / 750)))
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                try add(Coordinate(latitude: a.latitude + (b.latitude-a.latitude)*t, longitude: a.longitude + (b.longitude-a.longitude)*t))
            }
        }
        return result.sorted()
    }
}

struct OfflineGraphNode: Codable { var id: Int64; var coordinate: Coordinate }
struct OfflineGraphEdge: Codable, Hashable {
    var from: Int64; var to: Int64; var way: Int64
    var surface: Int; var name: String; var incline: Double
}
struct OfflineTurnRule: Codable, Hashable {
    var via: Int64; var fromWay: Int64; var toWays: [Int64]; var only: Bool; var uTurn: Bool
}
struct OfflineGraphTile: Codable {
    var version: Int; var x: Int; var y: Int; var generatedAt: Double
    var excludedWays: [Int64] = []; var blockedNodes: [Int64] = []
    var nodes: [OfflineGraphNode]; var edges: [OfflineGraphEdge]; var restrictions: [OfflineTurnRule]
    func validate(for id: OfflineTileID) throws {
        guard version == 1, x == id.x, y == id.y, generatedAt.isFinite,
              nodes.count <= 150_000, edges.count <= 350_000 else { throw LocalRoutingError.noData }
        var ids: Set<Int64> = []
        for node in nodes {
            guard ids.insert(node.id).inserted, (-90...90).contains(node.coordinate.latitude),
                  (-180...180).contains(node.coordinate.longitude) else { throw LocalRoutingError.noData }
        }
        guard edges.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && $0.incline.isFinite }) else { throw LocalRoutingError.noData }
    }
}

enum LocalRoutingError: LocalizedError {
    case noData, tooLarge, outside, noConnection, timedOut, ambiguous
    case waypointOffNetwork(String)
    var errorDescription: String? {
        switch self {
        case .noData: return "Für dieses Gebiet fehlen lokale Wegedaten. Verbinde den Pi, um sie auf das iPhone zu laden."
        case .tooLarge: return "Der Bereich ist zu groß. Bitte die Tour für die lokale Rückführung in kürzere Etappen aufteilen."
        case .outside: return "Lokaler Routenbereich verlassen. Die gespeicherte Tour bleibt auf der Karte."
        case .noConnection: return "Kein passender lokaler Anschluss gefunden. Folge der gespeicherten Tour auf der Karte."
        case .timedOut: return "Die lokale Suche wurde begrenzt. Beim Weiterfahren wird sie erneut versucht."
        case .ambiguous: return "Dein Weg ist noch nicht eindeutig erkennbar. Die nächste genaue Position wird abgewartet."
        case .waypointOffNetwork(let name):
            return "Bei „\(name)“ wurde im Umkreis von 250 m kein nutzbarer Fahrradweg oder Straßenanschluss gefunden. Setze diesen Punkt näher an eine Straße oder einen Radweg."
        }
    }
}

/// Immutable after construction, safe to share with a detached routing task.
final class OfflineGraph: @unchecked Sendable {
    let nodes: [Int64: Coordinate]
    let edges: [OfflineGraphEdge]
    let outgoing: [Int64: [Int]]
    let turns: [Int64: [OfflineTurnRule]]
    let tiles: Set<OfflineTileID>
    private let cells: [String: [Int]]
    init(tiles input: [OfflineGraphTile]) throws {
        var nodes: [Int64: Coordinate] = [:]
        var byWay: [Int64: Set<OfflineGraphEdge>] = [:]
        var excluded: Set<Int64> = [], blocked: Set<Int64> = []
        var rules: Set<OfflineTurnRule> = []
        for tile in input {
            try tile.validate(for: OfflineTileID(x: tile.x, y: tile.y))
            for node in tile.nodes {
                if let old = nodes[node.id], old.distance(to: node.coordinate) > 1 {
                    // Mixed map revisions must be refreshed, never silently joined.
                    throw LocalRoutingError.noData
                }
                nodes[node.id] = node.coordinate
            }
            excluded.formUnion(tile.excludedWays); blocked.formUnion(tile.blockedNodes)
            for (way, edges) in Dictionary(grouping: tile.edges, by: \.way) {
                if let previous = byWay[way] { byWay[way] = previous.intersection(edges) }
                else { byWay[way] = Set(edges) }
            }
            rules.formUnion(tile.restrictions)
            guard nodes.count <= 350_000 else { throw LocalRoutingError.tooLarge }
        }
        self.nodes = nodes
        self.edges = byWay.filter { !excluded.contains($0.key) }.values.flatMap { $0 }.filter { !blocked.contains($0.from) && !blocked.contains($0.to) }.sorted { ($0.from, $0.to, $0.way) < ($1.from, $1.to, $1.way) }
        guard self.edges.count <= 800_000 else { throw LocalRoutingError.tooLarge }
        self.tiles = Set(input.map { OfflineTileID(x: $0.x, y: $0.y) })
        var outgoing: [Int64: [Int]] = [:], cells: [String: [Int]] = [:]
        for (i, edge) in self.edges.enumerated() {
            outgoing[edge.from, default: []].append(i)
            guard let a = nodes[edge.from], let b = nodes[edge.to] else { continue }
            // 0.002° bins bound matching work independently of the entire tour length.
            let ax = Int(floor(a.longitude / 0.002)), bx = Int(floor(b.longitude / 0.002))
            let ay = Int(floor(a.latitude / 0.002)), by = Int(floor(b.latitude / 0.002))
            guard abs(ax-bx) < 300, abs(ay-by) < 300 else { throw LocalRoutingError.noData }
            for x in min(ax,bx)...max(ax,bx) { for y in min(ay,by)...max(ay,by) { cells["\(x):\(y)", default: []].append(i) } }
        }
        self.outgoing = outgoing; self.cells = cells
        self.turns = Dictionary(grouping: rules, by: \.via)
    }

    struct Match { var edge: Int; var t: Double; var point: Coordinate; var distance: Double }
    func matches(_ point: Coordinate, heading: Double? = nil, maxDistance: Double = 25) -> [Match] {
        guard maxDistance.isFinite, (0...1_000).contains(maxDistance),
              point.latitude.isFinite, point.longitude.isFinite else { return [] }
        // Search every bin touched by the requested radius, including at high
        // latitudes where a longitude bin is much narrower than 200 metres.
        let latitudeRadius = maxDistance / 110_000
        let longitudeRadius = latitudeRadius / max(0.01, cos(point.latitude * .pi / 180))
        let minX = Int(floor((point.longitude - longitudeRadius) / 0.002))
        let maxX = Int(floor((point.longitude + longitudeRadius) / 0.002))
        let minY = Int(floor((point.latitude - latitudeRadius) / 0.002))
        let maxY = Int(floor((point.latitude + latitudeRadius) / 0.002))
        var candidates: Set<Int> = []
        for x in minX...maxX { for y in minY...maxY { candidates.formUnion(cells["\(x):\(y)"] ?? []) } }
        let matches = candidates.compactMap { i -> Match? in
            let edge = edges[i]
            guard let a = nodes[edge.from], let b = nodes[edge.to] else { return nil }
            if let heading, LocalGeometry.angle(heading, LocalGeometry.bearing(a, b)) > 40 { return nil }
            let projection = LocalGeometry.project(point, onto: a, b)
            guard projection.distance <= maxDistance else { return nil }
            return Match(edge: i, t: projection.t, point: projection.point, distance: projection.distance)
        }.sorted { $0.distance == $1.distance ? $0.edge < $1.edge : $0.distance < $1.distance }
        guard let nearest = matches.first else { return [] }
        return matches.filter { $0.distance <= nearest.distance + 2 }
    }
    func allows(previous: Int64, incomingWay: Int64, edge: OfflineGraphEdge) -> Bool {
        for rule in turns[edge.from] ?? [] where rule.fromWay == incomingWay {
            if rule.only && (!rule.toWays.contains(edge.way) || (rule.uTurn ? edge.to != previous : edge.to == previous)) { return false }
            if !rule.only && rule.toWays.contains(edge.way) && (!rule.uTurn || edge.to == previous) { return false }
        }
        return true
    }
}

enum LocalGeometry {
    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let x = (b.longitude-a.longitude) * cos((a.latitude+b.latitude) * .pi / 360)
        return atan2(x, b.latitude-a.latitude) * 180 / .pi
    }
    static func angle(_ a: Double, _ b: Double) -> Double {
        let d = abs((a-b).truncatingRemainder(dividingBy: 360)); return min(d, 360-d)
    }
    static func project(_ p: Coordinate, onto a: Coordinate, _ b: Coordinate) -> (t: Double, point: Coordinate, distance: Double) {
        let scale = cos(p.latitude * .pi / 180)
        let dx = (b.longitude-a.longitude)*scale, dy = b.latitude-a.latitude
        let t = min(1, max(0, ((p.longitude-a.longitude)*scale*dx + (p.latitude-a.latitude)*dy) / max(1e-20, dx*dx+dy*dy)))
        let point = Coordinate(latitude: a.latitude + t*(b.latitude-a.latitude), longitude: a.longitude + t*(b.longitude-a.longitude))
        return (t, point, p.distance(to: point))
    }
}
