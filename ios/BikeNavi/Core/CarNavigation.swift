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
    mutating func announcement(progress: RouteProgress, speed: Double, following: (maneuver: Maneuver, gap: Double)?) -> String? {
        guard progress.distanceFromRoute <= 35, let next = progress.nextManeuver, next.type != 11 else { return nil }
        let speed = min(70, max(0, speed))
        let distance = progress.distanceToManeuver
        let stage = distance <= max(25, speed * 3) ? 3 : distance <= max(80, speed * 12) ? 2 : distance <= max(250, speed * 35) ? 1 : 0
        guard stage > 0, stage > (stages[next.coordinateIndex] ?? 0) else { return nil }
        stages[next.coordinateIndex] = stage
        let rounded = max(10, Int((distance / 10).rounded()) * 10)
        let prefix = stage == 3 ? "Jetzt: " : "In \(rounded) Metern: "
        var text = prefix + next.carInstruction
        if let following, following.gap <= max(100, speed * 8) {
            text += " Danach in \(max(10, Int((following.gap / 10).rounded()) * 10)) Metern: " + following.maneuver.carInstruction
        }
        return text
    }
}
