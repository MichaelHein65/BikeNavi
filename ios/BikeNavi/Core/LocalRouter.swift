import Foundation

struct LocalNavigationState: Codable, Equatable {
    var connector: CalculatedRoute?
    var rejoinIndex: Int?
    var originalProgress = 0.0
    var usedUnpaved = 0.0
    var routeProgress = 0.0
}

struct LocalConnection {
    var connector: CalculatedRoute
    var rejoinIndex: Int
    var unpavedDistance: Double
    var startAccessDistance: Double
    var endAccessDistance: Double
}

enum LocalRouteMetrics {
    static let paved: Set<Int> = [1, 3, 4, 5, 6, 14]
    static func distances(_ route: CalculatedRoute) -> [Double] {
        var result = [0.0]
        for (a,b) in zip(route.coordinates, route.coordinates.dropFirst()) { result.append(result.last! + a.distance(to: b)) }
        return result
    }
    static func unpaved(_ route: CalculatedRoute, from: Double = 0, to: Double = .infinity) -> Double {
        let distances = distances(route)
        return route.coloredSections.filter { !paved.contains($0.surface) }.reduce(0) { total, section in
            total + max(0, min(to, distances[section.endIndex]) - max(from, distances[section.startIndex]))
        }
    }
    static func nextWaypointIndex(route: CalculatedRoute, waypoints: [Waypoint], traveled: Double) -> Int {
        let distances = distances(route)
        if let indices = route.waypointIndices, indices.count == waypoints.count,
           indices.allSatisfy({ route.coordinates.indices.contains($0) }), indices == indices.sorted() {
            return indices.dropFirst().first(where: { distances[$0] >= traveled - 3 }) ?? route.coordinates.count-1
        }
        var lower = 0
        for waypoint in waypoints.dropFirst().dropLast() {
            let candidates = lower..<route.coordinates.count
            guard let nearest = candidates.min(by: { route.coordinates[$0].distance(to: waypoint.coordinate) < route.coordinates[$1].distance(to: waypoint.coordinate) }) else { continue }
            lower = nearest
            // Only a position beyond the waypoint counts as passed, never a 25 m shortcut.
            if distances[nearest] >= traveled - 3 { return nearest }
        }
        return route.coordinates.count-1
    }
    static func combined(original: CalculatedRoute, state: LocalNavigationState?) -> CalculatedRoute {
        guard let connector = state?.connector, let join = state?.rejoinIndex,
              original.coordinates.indices.contains(join), connector.coordinates.count > 1 else { return original }
        var result = connector
        let offset = connector.coordinates.count - 1
        result.coordinates += original.coordinates.dropFirst(join + 1)
        // The old instruction at the join assumes the original approach direction.
        // Recompute it from the connector so "left" cannot become a wrong turn.
        result.maneuvers = connector.maneuvers.filter { $0.coordinateIndex < offset }
        if join+1 < original.coordinates.count {
            let incoming = LocalGeometry.bearing(result.coordinates[offset-1], result.coordinates[offset])
            let outgoing = LocalGeometry.bearing(result.coordinates[offset], result.coordinates[offset+1])
            var angle = (outgoing-incoming).truncatingRemainder(dividingBy: 360)
            if angle > 180 { angle -= 360 }; if angle < -180 { angle += 360 }
            let type = abs(angle) >= 150 ? 9 : abs(angle) < 30 ? 11 : angle > 0 ? 1 : 0
            let instruction = type == 9 ? "Wenden und der Tour folgen" : type == 1 ? "Rechts abbiegen und der Tour folgen" : type == 0 ? "Links abbiegen und der Tour folgen" : "Der geplanten Tour folgen"
            result.maneuvers.append(Maneuver(instruction: instruction, distance: 0, coordinateIndex: offset, type: type))
        } else {
            result.maneuvers.append(Maneuver(instruction: "Ziel erreicht", distance: 0, coordinateIndex: offset, type: 10))
        }
        result.maneuvers += original.maneuvers.filter { $0.coordinateIndex > join }.map {
            Maneuver(instruction: $0.instruction, distance: $0.distance, coordinateIndex: offset + $0.coordinateIndex - join, type: $0.type)
        }
        result.surfaceSections = connector.coloredSections + original.coloredSections.compactMap { s in
            guard s.endIndex > join else { return nil }
            return RouteSurfaceSection(startIndex: offset + max(join, s.startIndex) - join, endIndex: offset + s.endIndex - join, surface: s.surface)
        }
        result.intersectionContexts = (original.intersectionContexts ?? []).filter { $0.coordinateIndex >= join }.map {
            IntersectionContext(coordinateIndex: offset + $0.coordinateIndex - join, roads: $0.roads)
        }
        let originalDistance = distances(original)
        result.distance = distances(result).last ?? 0
        result.duration = connector.duration + original.duration * max(0, (originalDistance.last! - originalDistance[join]) / max(1, originalDistance.last!))
        result.ascent = original.ascent; result.descent = original.descent
        result.surfaces = [] // Totals from the original tour are not valid for the connector.
        result.warnings = original.warnings
        return result
    }
}

/// Bounded, turn-aware search: A* for planning, multi-target Dijkstra for rejoining.
/// Track unpaved metres as a search resource only when a hard surface budget applies.
/// Otherwise surface preferences are already included in the route cost.
enum LocalRouter {
    private struct Key: Hashable { var node: Int64; var previous: Int64; var way: Int64 }
    private struct Label { var key: Key; var cost: Double; var length: Double; var unpaved: Double; var parent: Int?; var edge: Int; var startT: Double }
    private struct Goal { var index: Int; var match: OfflineGraph.Match; var suffixUnpaved: Double; var suffixCost: Double }
    private struct Heap {
        var values: [(Double, Int)] = []
        mutating func push(_ value: (Double, Int)) {
            values.append(value); var i = values.count-1
            while i > 0 { let p = (i-1)/2; if values[p].0 <= values[i].0 { break }; values.swapAt(p,i); i=p }
        }
        mutating func pop() -> (Double, Int)? {
            guard !values.isEmpty else { return nil }
            if values.count == 1 { return values.removeLast() }
            let result = values[0]; values[0] = values.removeLast(); var i=0
            while 2*i+1 < values.count {
                var child = 2*i+1
                if child+1 < values.count && values[child+1].0 < values[child].0 { child += 1 }
                if values[i].0 <= values[child].0 { break }; values.swapAt(i,child); i=child
            }
            return result
        }
    }
    static func connect(graph: OfflineGraph, original: CalculatedRoute, waypoints: [Waypoint], profile: RidingProfile,
                        position: Coordinate, heading: Double?, traveled: Double, usedUnpaved: Double,
                        timeLimit: Double = 2, planning: Bool = false) throws -> LocalConnection {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeLimit)
        func check() throws {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime >= deadline { throw LocalRoutingError.timedOut }
        }
        try check()
        guard graph.tiles.contains(.at(position)) else { throw LocalRoutingError.outside }
        let starts = graph.matches(position, heading: heading, maxDistance: planning ? 250 : 25)
        guard !starts.isEmpty else {
            if planning { throw LocalRoutingError.waypointOffNetwork(waypoints.first?.name ?? "Start") }
            throw LocalRoutingError.ambiguous
        }
        // Do not jump between parallel or grade-separated ways solely due to GPS proximity.
        let physicalWays = Set(starts.map { graph.edges[$0.edge].way })
        if !planning, physicalWays.count > 1, starts.contains(where: { $0.t > 0.08 && $0.t < 0.92 }) { throw LocalRoutingError.ambiguous }
        let distances = LocalRouteMetrics.distances(original)
        let nextWaypoint = LocalRouteMetrics.nextWaypointIndex(route: original, waypoints: waypoints, traveled: traveled)
        let upper = distances[nextWaypoint]
        // Evaluate every covered vertex up to the next mandatory stop. A nearby
        // return leg can be kilometres ahead along a winding original route.
        let indices = planning ? [original.coordinates.count - 1] : original.coordinates.indices.filter {
            distances[$0] > traveled + 3 && distances[$0] <= upper && original.coordinates[$0].distance(to: position) <= 3_000
        }
        var suffixUnpaved = Array(repeating: 0.0, count: distances.count)
        var suffixCost = suffixUnpaved
        var surfaces = Array(repeating: 0, count: distances.count)
        for section in original.coloredSections {
            for i in section.startIndex..<section.endIndex { surfaces[i] = section.surface }
        }
        for i in stride(from: distances.count - 2, through: 0, by: -1) {
            let length = distances[i+1] - distances[i]
            let off = LocalRouteMetrics.paved.contains(surfaces[i]) ? 0.0 : length
            suffixUnpaved[i] = suffixUnpaved[i+1] + off
            suffixCost[i] = suffixCost[i+1] + length + off * ((profile.surface == .preferPaved ? 8 : 0) + (profile.bike == .road ? 3 : 0))
        }
        var goals: [Goal] = []
        for index in indices {
            try check()
            let headingIndex = min(index+1, original.coordinates.count-1)
            let approachIndex = max(0, index-1)
            let direction = LocalGeometry.bearing(original.coordinates[index == headingIndex ? approachIndex : index], original.coordinates[headingIndex])
            let matches = graph.matches(original.coordinates[index], heading: planning ? nil : direction, maxDistance: planning ? 250 : 8)
            if planning && matches.isEmpty { throw LocalRoutingError.waypointOffNetwork(waypoints.last?.name ?? "Ziel") }
            if !planning, Set(matches.map { graph.edges[$0.edge].way }).count > 1,
               matches.contains(where: { $0.t > 0.08 && $0.t < 0.92 }) { continue }
            for match in matches {
                let suffix = suffixUnpaved[index]
                guard profile.surface != .pavedOnly || usedUnpaved + suffix <= 100.0001 else { continue }
                goals.append(Goal(index: index, match: match, suffixUnpaved: suffix, suffixCost: suffixCost[index]))
            }
        }
        guard !goals.isEmpty else { throw LocalRoutingError.noConnection }
        let byNode = Dictionary(grouping: goals, by: { graph.edges[$0.match.edge].from })
        var labels: [Label] = [], frontier: [Key: [Int]] = [:], heap = Heap()
        var best: (score: Double, label: Int?, start: OfflineGraph.Match?, goal: Goal)?
        func length(_ edge: OfflineGraphEdge) -> Double { graph.nodes[edge.from]!.distance(to: graph.nodes[edge.to]!) }
        func unpaved(_ edge: OfflineGraphEdge, _ length: Double) -> Double { LocalRouteMetrics.paved.contains(edge.surface) ? 0 : length }
        func cost(_ edge: OfflineGraphEdge, _ length: Double) -> Double {
            let surfacePenalty = profile.surface == .preferPaved && !LocalRouteMetrics.paved.contains(edge.surface) ? 8.0 : 0
            let roadPenalty = profile.bike == .road && !LocalRouteMetrics.paved.contains(edge.surface) ? 3.0 : 0
            return length * (1 + surfacePenalty + roadPenalty + (profile.gentleHills ? max(0, edge.incline) / 5 : 0))
        }
        func legalBudget(_ metres: Double, goal: Goal? = nil) -> Bool {
            profile.surface != .pavedOnly || usedUnpaved + metres + (goal?.suffixUnpaved ?? 0) <= 100.0001
        }
        func dominates(_ a: Label, _ b: Label) -> Bool {
            a.cost <= b.cost && a.length <= b.length
                && (profile.surface != .pavedOnly || a.unpaved <= b.unpaved)
        }
        func add(_ label: Label) {
            guard label.length <= (planning ? 300_000 : 5_000), legalBudget(label.unpaved) else { return }
            let old = frontier[label.key] ?? []
            if old.contains(where: { dominates(labels[$0], label) }) { return }
            frontier[label.key] = old.filter { !dominates(label, labels[$0]) } + [labels.count]
            labels.append(label)
            let heuristic = planning ? graph.nodes[label.key.node]!.distance(to: original.coordinates.last!) : 0
            heap.push((label.cost + heuristic, labels.count-1))
        }
        for start in starts {
            let edge = graph.edges[start.edge], distance = length(graph.edges[start.edge])
            for goal in goals where goal.match.edge == start.edge && goal.match.t >= start.t {
                let part = distance*(goal.match.t-start.t)
                let off = start.distance + unpaved(edge, part) + goal.match.distance
                if legalBudget(off, goal: goal) {
                    let score = start.distance + cost(edge, part) + goal.match.distance + goal.suffixCost
                    if best == nil || score < best!.score - 0.01 { best = (score, nil, start, goal) }
                }
            }
            let part = distance*(1-start.t)
            add(Label(key: Key(node: edge.to, previous: edge.from, way: edge.way), cost: start.distance + cost(edge, part), length: part,
                      unpaved: start.distance + unpaved(edge, part), parent: nil, edge: start.edge, startT: start.t))
        }
        var iterations = 0
        while let (score, id) = heap.pop() {
            if let best, score > best.score { break }
            iterations += 1
            if iterations % 128 == 0 {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    if best != nil { break }
                    throw LocalRoutingError.timedOut
                }
            }
            guard labels.count < 250_000 else { throw LocalRoutingError.timedOut }
            let label = labels[id]
            // Replaced labels remain for path reconstruction, but must not expand.
            guard frontier[label.key]?.contains(id) == true else { continue }
            for goal in byNode[label.key.node] ?? [] {
                let edge = graph.edges[goal.match.edge]
                guard graph.allows(previous: label.key.previous, incomingWay: label.key.way, edge: edge) else { continue }
                let part = length(edge)*goal.match.t
                let off = label.unpaved + unpaved(edge, part) + goal.match.distance
                guard legalBudget(off, goal: goal) else { continue }
                let total = label.cost + cost(edge, part) + goal.match.distance + goal.suffixCost
                if best == nil || total < best!.score - 0.01 { best = (total, id, nil, goal) }
            }
            for edgeID in graph.outgoing[label.key.node] ?? [] {
                let edge = graph.edges[edgeID]
                guard graph.allows(previous: label.key.previous, incomingWay: label.key.way, edge: edge),
                      (planning || graph.nodes[edge.to]!.distance(to: position) <= 3_000) else { continue }
                let distance = length(edge)
                add(Label(key: Key(node: edge.to, previous: edge.from, way: edge.way),
                          cost: label.cost + cost(edge, distance) + (edge.to == label.key.previous ? 25 : 0),
                          length: label.length + distance, unpaved: label.unpaved + unpaved(edge, distance),
                          parent: id, edge: edgeID, startT: 0))
            }
        }
        try Task.checkCancellation()
        guard let best else { throw LocalRoutingError.noConnection }
        var legs: [(edge: Int, start: Double, end: Double)] = []
        if var id = best.label {
            while true {
                let label = labels[id]; legs.append((label.edge, label.startT, 1))
                guard let parent = label.parent else { break }; id = parent
            }
            legs.reverse(); legs.append((best.goal.match.edge, 0, best.goal.match.t))
        } else if let start = best.start { legs = [(start.edge, start.t, best.goal.match.t)] }
        var points: [Coordinate] = [], sections: [RouteSurfaceSection] = [], names: [String] = []
        func append(_ point: Coordinate, surface: Int, name: String) {
            if let last = points.last, last.distance(to: point) < 0.05 { return }
            if !points.isEmpty { sections.append(RouteSurfaceSection(startIndex: points.count-1, endIndex: points.count, surface: surface)); names.append(name) }
            points.append(point)
        }
        for leg in legs {
            let edge = graph.edges[leg.edge], a = graph.nodes[edge.from]!, b = graph.nodes[edge.to]!
            func interpolate(_ t: Double) -> Coordinate { Coordinate(latitude: a.latitude+(b.latitude-a.latitude)*t, longitude: a.longitude+(b.longitude-a.longitude)*t) }
            if points.isEmpty { append(interpolate(leg.start), surface: edge.surface, name: edge.name) }
            append(interpolate(leg.end), surface: edge.surface, name: edge.name)
        }
        append(original.coordinates[best.goal.index], surface: 0, name: "Geplante Tour")
        guard points.count >= 2 else { throw LocalRoutingError.noConnection }
        var maneuvers = [Maneuver(instruction: "Der Verbindung zur Tour folgen", distance: 0, coordinateIndex: 0, type: 11)]
        for i in 1..<(points.count-1) {
            let incoming = LocalGeometry.bearing(points[i-1], points[i]), outgoing = LocalGeometry.bearing(points[i], points[i+1])
            var turn = (outgoing-incoming).truncatingRemainder(dividingBy: 360)
            if turn > 180 { turn -= 360 }; if turn < -180 { turn += 360 }
            guard abs(turn) >= 30 else { continue }
            let type = abs(turn) >= 150 ? 9 : turn > 0 ? 1 : 0
            let name = names.indices.contains(i) && !names[i].isEmpty ? " auf \(names[i])" : ""
            maneuvers.append(Maneuver(instruction: type == 9 ? "Wenden" : (type == 1 ? "Rechts abbiegen" : "Links abbiegen") + name,
                                      distance: 0, coordinateIndex: i, type: type))
        }
        maneuvers.append(Maneuver(instruction: "Der geplanten Tour folgen", distance: 0, coordinateIndex: points.count-1, type: 11))
        var connector = CalculatedRoute(id: UUID(), coordinates: points, distance: 0, duration: 0, ascent: 0, descent: 0,
            maneuvers: maneuvers, surfaces: [], warnings: [], provider: "BikeNavi lokal · OpenStreetMap", calculatedAt: Date().timeIntervalSince1970,
            surfaceSections: sections)
        connector.distance = LocalRouteMetrics.distances(connector).last ?? 0
        connector.duration = connector.distance / 4.5
        let off = LocalRouteMetrics.unpaved(connector) + position.distance(to: points[0])
        guard legalBudget(off, goal: best.goal) else { throw LocalRoutingError.noConnection }
        return LocalConnection(connector: connector, rejoinIndex: best.goal.index, unpavedDistance: off,
                               startAccessDistance: position.distance(to: points[0]), endAccessDistance: best.goal.match.distance)
    }
}

extension LocalRouteMetrics {
    /// Accept movement along the fresh connector, cutting its travelled prefix.
    /// A different road/direction rejects the result instead of applying an old start.
    static func trim(_ route: CalculatedRoute, to position: Coordinate, heading: Double?) -> CalculatedRoute? {
        let cumulative = distances(route)
        var best: (i: Int, point: Coordinate, distance: Double)?
        for i in 0..<(route.coordinates.count-1) where cumulative[i] <= 250 {
            let a = route.coordinates[i], b = route.coordinates[i+1]
            if let heading, LocalGeometry.angle(heading, LocalGeometry.bearing(a,b)) > 75 { continue }
            let projection = LocalGeometry.project(position, onto: a,b)
            if best == nil || projection.distance < best!.distance { best = (i, projection.point, projection.distance) }
        }
        guard let best, best.distance <= 25 else { return nil }
        var result = route
        result.coordinates = [best.point] + route.coordinates.dropFirst(best.i+1)
        result.maneuvers = route.maneuvers.filter { $0.coordinateIndex > best.i }.map {
            Maneuver(instruction: $0.instruction, distance: $0.distance, coordinateIndex: $0.coordinateIndex-best.i, type: $0.type)
        }
        result.surfaceSections = route.coloredSections.filter { $0.endIndex > best.i }.map {
            RouteSurfaceSection(startIndex: max(0,$0.startIndex-best.i), endIndex: $0.endIndex-best.i, surface: $0.surface)
        }
        result.distance = distances(result).last ?? 0
        result.duration = result.distance / 4.5
        return result
    }
}


extension LocalRouter {
    /// Entire itinerary is searched on the phone, using the same access rules
    /// and surface budget as navigation. No routing service is involved.
    static func plan(graph: OfflineGraph, document: TourDocument) throws -> CalculatedRoute {
        guard document.canCalculateRoute else { throw LocalRoutingError.noConnection }
        var result: CalculatedRoute?
        var indices = [0]
        var used = 0.0
        var accessWarnings: [String] = []
        for (a, b) in zip(document.waypoints, document.waypoints.dropFirst()) {
            try Task.checkCancellation()
            let seed = CalculatedRoute(id: UUID(), coordinates: [a.coordinate, b.coordinate], distance: 0,
                duration: 0, ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [],
                provider: "BikeNavi iPhone · OpenStreetMap", calculatedAt: Date().timeIntervalSince1970)
            let connection = try connect(graph: graph, original: seed, waypoints: [a,b], profile: document.profile,
                position: a.coordinate, heading: nil, traveled: 0, usedUnpaved: used, timeLimit: 8, planning: true)
            var leg = connection.connector
            for (point, distance) in [(a, connection.startAccessDistance), (b, connection.endAccessDistance)] where distance > 25 {
                let warning = "Zugang bei „\(point.name)“: ca. \(Int(distance.rounded())) m zum erfassten Wegenetz. Die Verbindung ist ungeprüft; Zugang vor Ort prüfen und gegebenenfalls schieben."
                if !accessWarnings.contains(warning) { accessWarnings.append(warning) }
            }
            leg.maneuvers[0].instruction = "Der Route folgen"
            if connection.endAccessDistance > 25, leg.coordinates.count >= 2 {
                leg.maneuvers.insert(Maneuver(instruction: "Zugang zu „\(b.name)“ vor Ort prüfen, gegebenenfalls schieben",
                    distance: connection.endAccessDistance, coordinateIndex: leg.coordinates.count - 2, type: 11),
                    at: leg.maneuvers.count - 1)
            }
            // A selected coordinate may lie just beside the mapped road.
            // Preserve its access segment explicitly instead of silently dropping it.
            if leg.coordinates[0].distance(to: a.coordinate) > 0.05 {
                let sections = leg.coloredSections
                leg.coordinates.insert(a.coordinate, at: 0)
                leg.surfaceSections = [RouteSurfaceSection(startIndex: 0, endIndex: 1, surface: 0)] + sections.map {
                    RouteSurfaceSection(startIndex: $0.startIndex+1, endIndex: $0.endIndex+1, surface: $0.surface)
                }
                leg.maneuvers = leg.maneuvers.map { Maneuver(instruction: $0.instruction, distance: $0.distance, coordinateIndex: $0.coordinateIndex+1, type: $0.type) }
            }
            if connection.startAccessDistance > 25 {
                leg.maneuvers.insert(Maneuver(instruction: "Zugang zum Routenstart vor Ort prüfen, gegebenenfalls schieben",
                    distance: connection.startAccessDistance, coordinateIndex: 0, type: 11), at: 0)
            }
            used += LocalRouteMetrics.unpaved(leg)
            guard document.profile.surface != .pavedOnly || used <= 100.0001 else { throw LocalRoutingError.noConnection }
            if var joined = result {
                let offset = joined.coordinates.count - 1
                let sections = joined.coloredSections
                joined.coordinates += leg.coordinates.dropFirst()
                joined.surfaceSections = sections + leg.coloredSections.map {
                    RouteSurfaceSection(startIndex: $0.startIndex+offset, endIndex: $0.endIndex+offset, surface: $0.surface)
                }
                joined.maneuvers.removeLast()
                joined.maneuvers += leg.maneuvers.map {
                    Maneuver(instruction: $0.instruction, distance: $0.distance, coordinateIndex: $0.coordinateIndex+offset, type: $0.type)
                }
                result = joined
            } else { result = leg }
            indices.append(result!.coordinates.count-1)
        }
        guard var route = result else { throw LocalRoutingError.noConnection }
        route.waypointIndices = indices
        route.provider = "BikeNavi iPhone · OpenStreetMap"
        route.distance = LocalRouteMetrics.distances(route).last ?? 0
        route.duration = route.distance / 4.5
        route.maneuvers[route.maneuvers.count-1] = Maneuver(instruction: "Ziel erreicht", distance: 0, coordinateIndex: route.coordinates.count-1, type: 10)
        let cumulative = LocalRouteMetrics.distances(route)
        var totals: [String: Double] = [:]
        for section in route.coloredSections {
            totals[SurfaceKind(code: section.surface).title, default: 0] += cumulative[section.endIndex] - cumulative[section.startIndex]
        }
        route.surfaces = totals.sorted { $0.key < $1.key }.map {
            SurfaceSummary(name: $0.key, distance: $0.value, percentage: $0.value / max(1,route.distance) * 100)
        }
        route.intersectionContexts = route.maneuvers.compactMap { maneuver in
            let point = route.coordinates[maneuver.coordinateIndex]
            let matches = graph.matches(point, maxDistance: 2)
            let nodes = Set(matches.flatMap { match -> [Int64] in
                let edge = graph.edges[match.edge]
                return [edge.from, edge.to].filter { graph.nodes[$0]!.distance(to: point) < 2 }
            })
            let roads = nodes.flatMap { node in
                (graph.outgoing[node] ?? []).map { index in
                    let edge = graph.edges[index]
                    return ContextRoad(coordinates: [graph.nodes[edge.from]!, graph.nodes[edge.to]!], kind: 0)
                }
            }
            return roads.isEmpty ? nil : IntersectionContext(coordinateIndex: maneuver.coordinateIndex, roads: roads)
        }
        route.warnings = accessWarnings + ["Höhenwerte und Fahrzeit sind lokal nur eingeschränkt verfügbar."]
        return route
    }
}


extension CalculatedRoute {
    var needsLocalSurfaceRepair: Bool {
        coordinates.count > 1 && provider.hasPrefix("BikeNavi iPhone") && surfaceSections != coloredSections
    }

    /// Recover metadata from the saved graph without changing the user's route.
    /// Both segment endpoints must lie on the same mapped edge. Ambiguous or
    /// unmapped access segments remain unknown instead of guessing a surface.
    func repairingLocalSurfaces(graph: OfflineGraph) -> CalculatedRoute {
        guard needsLocalSurfaceRepair else { return self }
        var result = self
        var sections: [RouteSurfaceSection] = []
        for i in 0..<(coordinates.count-1) {
            let a = coordinates[i], b = coordinates[i+1]
            let middle = Coordinate(latitude:(a.latitude+b.latitude)/2,longitude:(a.longitude+b.longitude)/2)
            let candidates = graph.matches(middle,maxDistance:1).filter { match in
                let edge = graph.edges[match.edge]
                let from = graph.nodes[edge.from]!, to = graph.nodes[edge.to]!
                return LocalGeometry.project(a,onto:from,to).distance <= 1 && LocalGeometry.project(b,onto:from,to).distance <= 1
            }
            let surfaces = Set(candidates.map { graph.edges[$0.edge].surface })
            sections.append(RouteSurfaceSection(startIndex:i,endIndex:i+1,surface:surfaces.count == 1 ? surfaces.first! : 0))
        }
        result.surfaceSections = sections
        let cumulative = LocalRouteMetrics.distances(result)
        var totals: [String:Double] = [:]
        for section in sections {
            totals[section.kind.title,default:0] += cumulative[section.endIndex]-cumulative[section.startIndex]
        }
        result.surfaces = totals.sorted { $0.key < $1.key }.map {
            SurfaceSummary(name:$0.key,distance:$0.value,percentage:$0.value/max(1,cumulative.last ?? 0)*100)
        }
        return result
    }
}
