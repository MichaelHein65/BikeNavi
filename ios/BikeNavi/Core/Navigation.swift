import Foundation

struct RouteProgress {
    var traveled: Double
    var remaining: Double
    var distanceFromRoute: Double
    var nextManeuver: Maneuver?
    var distanceToManeuver: Double
}

struct RouteTracker {
    private(set) var lastProgress = 0.0
    private(set) var lastTimestamp: Double?

    mutating func update(position: Coordinate, timestamp: Double, route: CalculatedRoute) -> RouteProgress? {
        guard route.coordinates.count > 1 else { return nil }
        let radians = Double.pi / 180
        let scaleX = cos(position.latitude * radians) * 111_320
        let scaleY = 111_320.0
        var cumulative = [0.0]
        for i in 1..<route.coordinates.count {
            cumulative.append(cumulative.last! + route.coordinates[i - 1].distance(to: route.coordinates[i]))
        }
        let elapsed = max(0, timestamp - (lastTimestamp ?? timestamp))
        // A local window avoids jumping to the return leg of a loop. After a long
        // interruption the window grows to permit recovery without fake progress.
        let maximumForward = lastTimestamp == nil ? Double.infinity : max(200, elapsed * 20)
        var best: (distance: Double, progress: Double)?
        for i in 0..<(route.coordinates.count - 1) {
            guard cumulative[i + 1] >= max(0, lastProgress - 150),
                  cumulative[i] <= lastProgress + maximumForward else { continue }
            let a = route.coordinates[i], b = route.coordinates[i + 1]
            let ax = (a.longitude - position.longitude) * scaleX
            let ay = (a.latitude - position.latitude) * scaleY
            let bx = (b.longitude - position.longitude) * scaleX
            let by = (b.latitude - position.latitude) * scaleY
            let dx = bx - ax, dy = by - ay
            let t = min(1, max(0, -(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)))
            let distance = hypot(ax + t * dx, ay + t * dy)
            let progress = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
            if best == nil || distance < best!.distance - 1 { best = (distance, progress) }
        }
        guard let best else { return nil }
        if best.distance < 60 { lastProgress = best.progress; lastTimestamp = timestamp }
        let next = route.maneuvers.first { m in
            m.coordinateIndex < cumulative.count && cumulative[m.coordinateIndex] > lastProgress + 12
        }
        return RouteProgress(traveled: lastProgress, remaining: max(0, cumulative.last! - lastProgress),
                             distanceFromRoute: best.distance, nextManeuver: next,
                             distanceToManeuver: next.map { max(0, cumulative[$0.coordinateIndex] - lastProgress) } ?? 0)
    }
}

/// Avoid reacting to ordinary GPS drift or a brief detour. A new route is
/// requested only after the rider has been at least 80 m away for 10 seconds;
/// requests are then limited to one every 90 seconds.
struct ReroutePolicy {
    private(set) var offRouteSince: Double?
    private(set) var lastRerouteAt: Double?
    static let deviation = 80.0
    static let confirmationDuration = 10.0
    static let cooldown = 90.0

    mutating func observe(distanceFromRoute: Double, timestamp: Double) -> Bool {
        guard distanceFromRoute.isFinite, timestamp.isFinite else { return false }
        guard distanceFromRoute >= Self.deviation else {
            offRouteSince = nil
            return false
        }
        if offRouteSince == nil { offRouteSince = timestamp }
        guard timestamp - (offRouteSince ?? timestamp) >= Self.confirmationDuration,
              timestamp - (lastRerouteAt ?? -.infinity) >= Self.cooldown else { return false }
        lastRerouteAt = timestamp
        offRouteSince = nil
        return true
    }
}

enum TrackFilter {
    static func accepts(_ point: TrackPoint, after previous: TrackPoint?, now: Double) -> Bool {
        guard point.accuracy >= 0, point.accuracy <= 50,
              abs(now - point.timestamp) < 15,
              (-90...90).contains(point.coordinate.latitude),
              (-180...180).contains(point.coordinate.longitude) else { return false }
        guard let previous, previous.segment == point.segment else { return true }
        let elapsed = point.timestamp - previous.timestamp
        guard elapsed >= 3 else { return false }
        let distance = previous.coordinate.distance(to: point.coordinate)
        // Avoid impossible GPS jumps while leaving ordinary cycling speeds intact.
        return distance / elapsed < 35 && (distance >= 3 || elapsed >= 20)
    }
}
