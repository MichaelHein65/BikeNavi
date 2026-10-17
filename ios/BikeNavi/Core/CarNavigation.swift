import Foundation

struct CarOptions: Codable, Equatable {
    var avoidHighways = false
    var avoidTolls = false
    var avoidFerries = false
    var summary: String {
        let exclusions = [(avoidHighways, "Autobahnen"), (avoidTolls, "Maut"), (avoidFerries, "Fähren")]
            .filter { $0.0 }.map { $0.1 }
        return exclusions.isEmpty ? "Schnellste Pkw-Route" : "Schnellste Pkw-Route · ohne " + exclusions.joined(separator: ", ")
    }
}

struct CarTimeSection: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var seconds: Double
}

enum CarNavigation {
    static let trafficNotice = "Fahrzeit geschätzt · ohne Live-Verkehr"
    static let onlineNotice = "Route gespeichert · Neuberechnung benötigt Internet und Pi"
    static func pending(ride: TourDocument) -> [Int] {
        ride.localNavigation?.carPendingWaypointOrdinals ?? Array(ride.waypoints.indices.dropFirst())
    }

    static func requiringUnvisitedStop(ride: TourDocument, route: CalculatedRoute, progress: RouteProgress, position: Coordinate) -> RouteProgress {
        let pending = pending(ride: ride)
        guard pending.count > 1, let first = pending.first, let indices = route.waypointIndices else { return progress }
        let slot = ride.localNavigation?.carRoute == nil ? first : indices.count - pending.count
        guard indices.indices.contains(slot), route.coordinates.indices.contains(indices[slot]) else { return progress }
        let index = indices[slot]
        guard progress.traveled > LocalRouteMetrics.distances(route)[index] + 50,
              position.distance(to: route.coordinates[index]) > 50 else { return progress }
        var held = progress
        held.snappedPosition = nil
        held.distanceFromRoute = max(60, progress.distanceFromRoute)
        return held
    }

    /// Only physically reached stops are consumed; an off-route shortcut never skips them.
    static func remaining(ride: TourDocument, route: CalculatedRoute, progress: RouteProgress, position: Coordinate) -> [Int] {
        var pending = pending(ride: ride)
        guard progress.snappedPosition != nil, progress.distanceFromRoute <= 25 else { return pending }
        let ordinals = pending
        let indices = route.waypointIndices ?? LocalRouteMetrics.waypointIndices(route: route,
            waypoints: ride.localNavigation?.carRoute == nil ? ride.waypoints :
                [Waypoint(name: "Start", coordinate: route.coordinates[0])] + ordinals.map { ride.waypoints[$0] })
        let distances = LocalRouteMetrics.distances(route)
        for ordinal in ordinals.dropLast() {
            let slot = ride.localNavigation?.carRoute == nil ? ordinal : (indices.count - ordinals.count + ordinals.firstIndex(of: ordinal)!)
            guard indices.indices.contains(slot), route.coordinates.indices.contains(indices[slot]) else { break }
            let index = indices[slot]
            guard progress.traveled >= distances[index] - 15, position.distance(to: route.coordinates[index]) <= 50 else { break }
            pending.removeFirst()
        }
        return pending
    }

    static func arrived(route: CalculatedRoute, progress: RouteProgress, pending: [Int], position: Coordinate) -> Bool {
        pending.count == 1 && progress.snappedPosition != nil && progress.remaining <= 25
            && route.coordinates.last.map { position.distance(to: $0) <= 35 } == true
    }

    static func following(route: CalculatedRoute, next: Maneuver?) -> (maneuver: Maneuver, gap: Double)? {
        guard let next else { return nil }
        let distances = LocalRouteMetrics.distances(route)
        guard distances.indices.contains(next.coordinateIndex),
              let following = route.maneuvers.first(where: { $0.coordinateIndex > next.coordinateIndex && $0.type != 11 }),
              distances.indices.contains(following.coordinateIndex) else { return nil }
        return (following, distances[following.coordinateIndex] - distances[next.coordinateIndex])
    }

    static func replacement(_ route: CalculatedRoute, origin: Coordinate, requestedAt: Double,
                            current: Coordinate, timestamp: Double, heading: Double?, accuracy: Double,
                            now: Double) -> RouteProgress? {
        guard now >= requestedAt, now - requestedAt <= 45, abs(now - timestamp) < 5,
              accuracy >= 0, accuracy <= 25, origin.distance(to: current) <= 2500 else { return nil }
        var tracker = RouteTracker()
        guard let progress = tracker.update(position: current, timestamp: timestamp, route: route,
            heading: heading, accuracy: accuracy, carNavigation: true), progress.snappedPosition != nil else { return nil }
        return progress
    }
}

/// Metres visible ahead of the car. Inputs and transitions use measured time,
/// so stop-and-go and frequent redraws do not oscillate or accelerate the camera.
struct CarAutoZoom {
    private(set) var lookAhead = 450.0
    private(set) var smoothedSpeed = 0.0
    private var lastTimestamp: Double?
    private var actionIndex: Int?

    mutating func update(speed: Double, timestamp: Double, progress: RouteProgress?, followingGap: Double? = nil,
                         active: Bool = true, fresh: Bool = true, rerouting: Bool = false) -> Double {
        guard active, fresh, !rerouting, speed.isFinite, timestamp.isFinite,
              lastTimestamp.map({ timestamp > $0 }) ?? true else { return lookAhead }
        let first = lastTimestamp == nil
        let elapsed = min(3, max(0, timestamp - (lastTimestamp ?? timestamp)))
        lastTimestamp = timestamp
        let measured = min(70, max(0, speed))
        smoothedSpeed = first ? measured : smoothedSpeed + (measured - smoothedSpeed) * (1 - exp(-elapsed / 4))
        let base = min(2200, max(300, 250 + smoothedSpeed * 40))
        var desired = base
        if let progress, progress.distanceFromRoute <= 35, let next = progress.nextManeuver, next.type != 11 {
            let distance = progress.distanceToManeuver
            let complex = [7, 8, 9, 12, 13].contains(next.type)
            let trigger = max(complex ? 260 : 180, smoothedSpeed * (complex ? 45 : 35))
            if distance <= trigger || (actionIndex == next.coordinateIndex && distance <= trigger * 1.25) {
                actionIndex = next.coordinateIndex
                desired = max(complex ? 260 : 180, distance + (complex ? 160 : 100))
                if let gap = followingGap, gap <= max(100, smoothedSpeed * 8) {
                    desired = max(desired, distance + gap + 100)
                }
            } else { actionIndex = nil }
        } else { actionIndex = nil }
        // The first fix establishes the speed view. Later changes take ~3 seconds.
        lookAhead = first ? desired : lookAhead + (desired - lookAhead) * (1 - exp(-elapsed / 3))
        return lookAhead
    }
}

struct CarVoiceGuidance {
    private var stages: [Int: Int] = [:]
    private var lastAnnouncement = -Double.infinity

    /// Traffic refreshes change point indices, not necessarily the next turn.
    mutating func rebase(from old: CalculatedRoute, to new: CalculatedRoute) {
        var remapped: [Int: Int] = [:]
        for maneuver in old.maneuvers {
            guard let stage = stages[maneuver.coordinateIndex], old.coordinates.indices.contains(maneuver.coordinateIndex) else { continue }
            let position = old.coordinates[maneuver.coordinateIndex]
            if let match = new.maneuvers.filter({ candidate in
                candidate.type == maneuver.type && candidate.carInstruction == maneuver.carInstruction
                    && new.coordinates.indices.contains(candidate.coordinateIndex)
                    && position.distance(to: new.coordinates[candidate.coordinateIndex]) <= 30
            }).min(by: { position.distance(to: new.coordinates[$0.coordinateIndex]) < position.distance(to: new.coordinates[$1.coordinateIndex]) }) {
                remapped[match.coordinateIndex] = max(remapped[match.coordinateIndex] ?? 0, stage)
            }
        }
        stages = remapped
    }

    mutating func announcement(progress: RouteProgress, speed: Double, following: (maneuver: Maneuver, gap: Double)?,
                               now: Double = Date().timeIntervalSince1970) -> String? {
        guard progress.distanceFromRoute <= 35, let next = progress.nextManeuver, next.type != 11, next.type != 10 else { return nil }
        let speed = min(70, max(0, speed))
        let distance = progress.distanceToManeuver
        // One advance notice and one immediate instruction, with breathing room
        // between utterances. Arrival is announced separately by AppState.
        let stage = distance <= min(90, max(25, speed * 3)) ? 2 : distance <= min(800, max(150, speed * 20)) ? 1 : 0
        guard stage > 0, stage > (stages[next.coordinateIndex] ?? 0),
              now - lastAnnouncement >= (stage == 2 ? 5 : 15) else { return nil }
        stages[next.coordinateIndex] = stage; lastAnnouncement = now
        let rounded = max(10, Int((distance / 10).rounded()) * 10)
        let prefix = stage == 2 ? "Jetzt: " : "In \(rounded) Metern: "
        var text = prefix + next.carInstruction
        if stage == 2, let following, following.gap <= max(100, speed * 8), following.maneuver.type != 10 {
            text += " Danach in \(max(10, Int((following.gap / 10).rounded()) * 10)) Metern: " + following.maneuver.carInstruction
        }
        return text
    }
}

struct CarSpeedLimit: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var kilometersPerHour: Double
}
struct CarLane: Codable, Equatable {
    var directions: [String]
    var follow: String?
    static func arrow(_ direction: String) -> String {
        switch direction {
        case "SLIGHT_LEFT": return "↖"
        case "LEFT", "SHARP_LEFT": return "←"
        case "LEFT_U_TURN": return "↶"
        case "SLIGHT_RIGHT": return "↗"
        case "RIGHT", "SHARP_RIGHT": return "→"
        case "RIGHT_U_TURN": return "↷"
        case "STRAIGHT": return "↑"
        default: return "?"
        }
    }
}
struct CarLaneSection: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var lanes: [CarLane]
}
struct CarTrafficSection: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var delaySeconds: Double
    var category: String
    var isRelevant: Bool { category == "ROAD_CLOSURE" || (delaySeconds.isFinite && delaySeconds > 0) }
    var title: String {
        switch category {
        case "JAM": return "Stau"
        case "ROAD_WORK": return "Baustelle"
        case "ROAD_CLOSURE": return "Sperrung"
        default: return "Verkehrsbehinderung"
        }
    }
}
struct CarTraffic: Codable, Equatable {
    var fetchedAt: Double
    var delaySeconds: Double
    var sections: [CarTrafficSection]
    func isFresh(now: Double) -> Bool { fetchedAt.isFinite && now >= fetchedAt && now - fetchedAt <= 300 }
}

extension CarNavigation {
    static let trafficRefreshInterval: TimeInterval = 300

    static func trafficRefreshDue(fetchedAt: Double, lastAttempt: Double, now: Double) -> Bool {
        now - fetchedAt >= trafficRefreshInterval && now - lastAttempt >= trafficRefreshInterval
    }

    /// Keep a quiet driving screen when fresh traffic has no impact; retain data-loss warnings.
    static func rideTrafficNotice(route: CalculatedRoute?, now: Double) -> String? {
        if let traffic = route?.carTraffic, traffic.isFresh(now: now), traffic.delaySeconds <= 0 { return nil }
        return trafficNotice(route: route, now: now)
    }

    static func trafficNotice(route: CalculatedRoute?, now: Double = Date().timeIntervalSince1970) -> String {
        guard let traffic = route?.carTraffic else { return trafficNotice }
        guard traffic.isFresh(now: now) else { return "Verkehrsdaten veraltet · Fahrzeit nur geschätzt" }
        let minutes = Int(ceil(max(0, traffic.delaySeconds) / 60))
        return "TomTom Live-Verkehr · +\(minutes) min · Stand vor \(Int(max(0, now - traffic.fetchedAt) / 60)) min"
    }

    /// A legal limit applies only to the matched current segment, never to an upcoming one.
    static func speedLimit(route: CalculatedRoute, progress: RouteProgress?, active: Bool) -> Double? {
        guard active, let progress, progress.snappedPosition != nil, progress.distanceFromRoute <= 25 else { return nil }
        let distances = LocalRouteMetrics.distances(route)
        return route.carSpeedLimits?.first { section in
            valid(start: section.startIndex, end: section.endIndex, distances: distances)
                && progress.traveled >= distances[section.startIndex] && progress.traveled < distances[section.endIndex]
                && section.kilometersPerHour.isFinite && section.kilometersPerHour > 0 && section.kilometersPerHour <= 300
        }?.kilometersPerHour
    }
    static func lanes(route: CalculatedRoute, progress: RouteProgress?, active: Bool) -> CarLaneSection? {
        guard active, let progress, progress.snappedPosition != nil, progress.distanceFromRoute <= 25 else { return nil }
        let distances = LocalRouteMetrics.distances(route)
        return route.carLaneSections?.first { section in
            valid(start: section.startIndex, end: section.endIndex, distances: distances)
                && progress.traveled >= distances[section.startIndex] && progress.traveled < distances[section.endIndex]
                && section.lanes.contains { $0.follow != nil }
        }
    }
    static func nextTraffic(route: CalculatedRoute, progress: RouteProgress?, now: Double) -> CarTrafficSection? {
        guard let traffic = route.carTraffic, traffic.isFresh(now: now), let progress,
              progress.snappedPosition != nil, progress.distanceFromRoute <= 25 else { return nil }
        let distances = LocalRouteMetrics.distances(route)
        return traffic.sections.first { $0.isRelevant && valid(start: $0.startIndex, end: $0.endIndex, distances: distances) && distances[$0.endIndex] > progress.traveled }
    }
    private static func valid(start: Int, end: Int, distances: [Double]) -> Bool {
        start >= 0 && end > start && end < distances.count
    }
}
